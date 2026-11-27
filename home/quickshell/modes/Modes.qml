pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Automatic modes: what you're doing right now, inferred, with a manual override.
//
//   class      a timed event from a class feed (gcal-url line labelled `class`,
//              see home/gcal-sync.nix), from lead_minutes before it until it ends
//   gaming     the focused window is fullscreen and is a game (Hyprland's
//              contentType "game", or a window class in [modes.gaming] classes)
//   deep_work  the Pomodoro widget's focus timer is running
//   normal     none of the above
//
// Exclusive, first match in `order` wins. Each mode's behaviour comes from
// settings.toml [modes.<name>] over `defaults` below (live: saved edits apply).
// A manual pick (launcher, `set()`) holds until the inferred mode changes, then
// automatic resumes; "auto" clears it at once.
//
// Read by: NotificationsBackend (dnd -> quiet), the island's ModeSource (chip +
// glance), the launcher's mode actions. Widgets (step 3) will key off `mode`.
Singleton {
  id: modes

  readonly property var order: ["class", "gaming", "deep_work"]
  readonly property var defaults: ({
    "class": { enabled: true, calendars: ["class"], lead_minutes: 5, dnd: true },
    "gaming": { enabled: true, classes: ["^steam_app_\\d+$", "^gamescope$"], dnd: true },
    "deep_work": { enabled: true, dnd: true },
    "normal": { dnd: false },
  })
  readonly property var info: ({
    "normal": { label: "Normal", icon: "sparkle", color: "#abb2bf" },
    "class": { label: "Class", icon: "graduation-cap", color: "#e5c07b" },
    "gaming": { label: "Gaming", icon: "game-controller", color: "#89ca78" },
    "deep_work": { label: "Deep work", icon: "brain", color: "#d55fde" },
  })

  // ---- config ----
  property var userConfig: ({})
  readonly property var config: {
    const out = {};
    for (const k in defaults) out[k] = Object.assign({}, defaults[k], userConfig[k] || {});
    return out;
  }
  function on(m) { return !!config[m] && config[m].enabled !== false; }

  readonly property string settingsPath: Quickshell.env("COEL_SETTINGS") || (Quickshell.env("HOME") + "/.nixos/settings.toml")
  FileView {
    path: modes.settingsPath
    watchChanges: true
    onFileChanged: settingsProc.running = true
    onLoaded: settingsProc.running = true
  }
  Process {
    id: settingsProc
    command: ["python3", Qt.resolvedUrl("../scripts/settings-table.py").toString().replace("file://", ""), "modes"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { modes.userConfig = JSON.parse(text) || {}; }
        catch (e) { console.warn("modes: bad settings JSON:", e); }
      }
    }
  }

  property real now: Date.now()
  Timer { interval: 30000; repeat: true; running: true; onTriggered: modes.now = Date.now() }

  // ---- class: the calendar file gcal-sync writes ----
  readonly property string dataDir: Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")
  property var events: []
  FileView {
    path: modes.dataDir + "/gcal-events.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { modes.events = JSON.parse(text()) || []; } catch (e) { modes.events = []; } }
    onLoadFailed: modes.events = []
  }
  function at(date, hhmm) {
    const d = date.split("-").map(Number), t = hhmm.split(":").map(Number);
    return new Date(d[0], d[1] - 1, d[2], t[0], t[1]).getTime();
  }
  // The class happening now (or starting within lead_minutes): {title, where, start, end} or null.
  readonly property var classNow: {
    const c = config["class"], cals = c.calendars || [];
    const lead = (Number(c.lead_minutes) || 0) * 60000, t = now;
    for (const e of events) {
      if (!e.start || !e.end || cals.indexOf(e.cal) < 0) continue;
      const s = at(e.date, e.start), f = at(e.date, e.end);
      if (t >= s - lead && t < f) return { title: e.title, where: e.where, start: s, end: f };
    }
    return null;
  }

  // ---- deep work: the Pomodoro widget's state file ----
  property bool focusRunning: false
  property real focusEndAt: 0
  FileView {
    path: modes.dataDir + "/pomodoro.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        const p = JSON.parse(text());
        modes.focusRunning = !!p.running && p.mode === "focus";
        modes.focusEndAt = p.endAt || 0;
      } catch (e) { modes.focusRunning = false; }
    }
  }
  readonly property bool focusNow: focusRunning && focusEndAt > now - 60000

  // ---- gaming: focused window, re-read on Hyprland focus/fullscreen events ----
  property bool gameRaw: false
  property string gameClass: ""
  // Debounced both ways: entering needs 2 s of a focused fullscreen game; leaving
  // needs 30 s without one, so alt-tabbing to Discord doesn't flap the mode.
  property bool gameNow: false
  Timer { id: gameOn; interval: 2000; onTriggered: modes.gameNow = true }
  Timer { id: gameOff; interval: 30000; onTriggered: modes.gameNow = false }
  onGameRawChanged: {
    if (gameRaw) { gameOff.stop(); if (!gameNow) gameOn.restart(); }
    else { gameOn.stop(); if (gameNow) gameOff.restart(); }
  }
  function isGame(w) {
    if (!w || !w.fullscreen) return false;
    if (w.contentType === "game") return true;
    for (const re of (config["gaming"].classes || [])) {
      try { if (new RegExp(re).test(w["class"] || "")) return true; } catch (e) {}
    }
    return false;
  }
  Process {
    id: activeProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        let w = null;
        try { w = JSON.parse(text); } catch (e) {}
        modes.gameRaw = modes.isGame(w);
        if (modes.gameRaw) modes.gameClass = w["class"] || "";
      }
    }
  }
  Timer { id: activeDebounce; interval: 150; onTriggered: activeProc.running = true }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      const n = event.name;
      if (n === "activewindowv2" || n === "fullscreen" || n === "closewindow" || n === "workspacev2" || n === "focusedmonv2")
        activeDebounce.restart();
    }
  }
  Component.onCompleted: activeProc.running = true

  // ---- the mode ----
  readonly property string inferred: {
    for (const m of order) {
      if (!on(m)) continue;
      if (m === "class" && classNow) return m;
      if (m === "gaming" && gameNow) return m;
      if (m === "deep_work" && focusNow) return m;
    }
    return "normal";
  }
  property string override: ""
  property string overrideFrom: ""
  onInferredChanged: if (override !== "" && inferred !== overrideFrom) override = ""
  // "auto" | "normal" | "class" | "gaming" | "deep_work"
  function set(m) {
    if (m === "auto" || !info[m]) { override = ""; return; }
    overrideFrom = inferred;
    override = m;
  }

  readonly property string mode: override !== "" ? override : inferred
  readonly property bool manual: override !== ""
  readonly property bool dnd: !!(config[mode] && config[mode].dnd)
  readonly property string label: info[mode].label
  // One short line about why: "COMP348 until 15:45", "steam_app_1091500", "focus session".
  readonly property string detail: {
    if (mode === "class" && classNow) return classNow.title + " until " + Qt.formatDateTime(new Date(classNow.end), "hh:mm");
    if (mode === "gaming" && gameNow) return gameClass;
    if (mode === "deep_work" && focusNow) return "focus until " + Qt.formatDateTime(new Date(focusEndAt), "hh:mm");
    return manual ? "set by hand" : "";
  }

  IpcHandler {
    target: "modes"
    function set(m: string): void { modes.set(m); }
    function get(): string { return modes.mode + (modes.manual ? " (manual)" : "") + (modes.detail ? " · " + modes.detail : ""); }
  }
}

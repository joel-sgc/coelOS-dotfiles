pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "../desktop/Layout.js" as DeskLayout

// Automatic modes: what you're doing right now, inferred, with a manual override.
// Design: example/Desktop Board.dc.html ("Seven modes", "who wins").
//
//   gaming     focused fullscreen game (Hyprland contentType "game", or a class regex)
//   class      a timed event from a gcal-url feed labelled `class` is on (0 min lead;
//              the pill does the warm-up countdown)
//   deep_work  a Pomodoro is running (its breaks keep the mode), or a calendar block
//              titled "focus" / "deep work" is on
//   printing   the printer isn't idle; a finished print counts until the plate is
//              cleared or 30 min have passed (fed by island/sources/PrinterSource.qml)
//   music      an Mpris player is playing (5 min of grace after it pauses)
//   evening    19:00 to 04:00
//   morning    the default ("default" after 12:00)
//
// First match in `order` wins. Per-mode options in settings.toml [modes.<name>]
// (enabled, dnd, sounds, pinned: desktop cards always shown in that mode).
// A manual pick holds `until` the inferred mode next changes ("event"), for an
// hour ("hour"), or until changed again ("forever"); the last two survive reloads
// (modes.json in the data dir).
//
// Read by: NotificationsBackend (dnd -> quiet), desktop/ (layout recipe + mode chip),
// the launcher's mode actions.
Singleton {
  id: modes

  readonly property var order: ["gaming", "class", "deep_work", "printing", "music", "evening", "morning"]
  readonly property var defaults: ({
    "gaming": { enabled: true, classes: ["^steam_app_\\d+$", "^gamescope$"], dnd: true },
    "class": { enabled: true, calendars: ["class"], lead_minutes: 0, dnd: true, sounds: false },
    "deep_work": { enabled: true, blocks: ["focus", "deep work"], dnd: true },
    "printing": { enabled: true, dnd: false },
    "music": { enabled: true, dnd: false },
    "evening": { enabled: true, from: 19, until: 4, dnd: false },
    "morning": { dnd: false },
  })
  readonly property var info: ({
    "gaming": { label: "gaming", icon: "game-controller", color: "#d19a66" },
    "class": { label: "class", icon: "chalkboard-teacher", color: "#61afef" },
    "deep_work": { label: "deep work", icon: "target", color: "#ef596f" },
    "printing": { label: "printing", icon: "printer", color: "#2bbac5" },
    "music": { label: "music", icon: "music-notes", color: "#89ca78" },
    "evening": { label: "evening", icon: "moon-stars", color: "#d55fde" },
    "morning": { label: "morning", icon: "sun-horizon", color: "#e5c07b" },
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

  // The clock. 30 s is plenty: every boundary that matters is minute-grained.
  property real now: Date.now()
  Timer { interval: 30000; repeat: true; running: true; onTriggered: modes.now = Date.now() }
  function hhmm(ms) { return Qt.formatDateTime(new Date(ms), "hh:mm"); }

  // ---- calendar (gcal-sync's file): classes and focus blocks ----
  readonly property string dataDir: Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")
  property var events: []
  FileView {
    path: modes.dataDir + "/gcal-events.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { modes.events = JSON.parse(text()) || []; } catch (e) { modes.events = []; } }
    onLoadFailed: modes.events = []
  }
  function at(date, hm) {
    const d = date.split("-").map(Number), t = hm.split(":").map(Number);
    return new Date(d[0], d[1] - 1, d[2], t[0], t[1]).getTime();
  }
  function eventNow(match, leadMs) {
    for (const e of events) {
      if (!e.start || !e.end || !match(e)) continue;
      const s = at(e.date, e.start), f = at(e.date, e.end);
      if (now >= s - leadMs && now < f) return { title: e.title, where: e.where, start: s, end: f };
    }
    return null;
  }
  readonly property var classNow: {
    const c = config["class"], cals = c.calendars || [];
    return eventNow(e => cals.indexOf(e.cal) >= 0, (Number(c.lead_minutes) || 0) * 60000);
  }
  readonly property var focusBlockNow: {
    const words = (config["deep_work"].blocks || []).map(w => String(w).toLowerCase());
    return eventNow(e => words.some(w => String(e.title).toLowerCase().startsWith(w)), 0);
  }

  // ---- Pomodoro (its state file) ----
  property bool pomoRunning: false
  property string pomoMode: "focus"
  property real pomoChangedAt: 0
  FileView {
    path: modes.dataDir + "/pomodoro.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const p = JSON.parse(text());
        const run = !!p.running, m = p.mode || "focus";
        if (run !== modes.pomoRunning || m !== modes.pomoMode) modes.pomoChangedAt = Date.now();
        modes.pomoRunning = run;
        modes.pomoMode = m;
      } catch (e) { modes.pomoRunning = false; }
    }
  }
  // A break waiting to be started still counts for 20 min; a reset back to an
  // idle focus timer ends the mode.
  readonly property bool pomoNow: pomoRunning || (pomoMode !== "focus" && now - pomoChangedAt < 20 * 60000)

  // ---- printer (set by PrinterSource) ----
  property string printerStatus: "idle"
  property string printerWhy: ""
  // When a print we watched end finished or failed (0: it ended before we were
  // looking, e.g. the P1S still reports a failure from yesterday).
  property real printerEndedAt: 0
  property bool plateCleared: false
  onPrinterStatusChanged: if (printerStatus !== "idle" && printerStatus !== "finished" && printerStatus !== "failed") plateCleared = false
  onPrinterEndedAtChanged: plateCleared = false
  function clearPlate() { plateCleared = true; }
  readonly property bool printingNow: ["heating", "printing", "paused"].indexOf(printerStatus) >= 0
    || ((printerStatus === "finished" || printerStatus === "failed") && printerEndedAt > 0
        && !plateCleared && now - printerEndedAt < 30 * 60000)

  // ---- music (Mpris) ----
  // (services/Music.qml picks the same way; playerctld is a proxy that mirrors
  // the real player, so it's skipped.)
  readonly property var player: {
    const ps = Mpris.players.values.filter(p => !/playerctld/i.test(p.dbusName || "") && !/playerctld/i.test(p.identity || ""));
    for (const p of ps) if (p.playbackState === MprisPlaybackState.Playing) return p;
    return ps.length ? ps[0] : null;
  }
  readonly property bool musicPlaying: !!player && player.playbackState === MprisPlaybackState.Playing
  property real musicStoppedAt: 0
  onMusicPlayingChanged: if (!musicPlaying) musicStoppedAt = Date.now()
  readonly property bool musicNow: musicPlaying || (musicStoppedAt > 0 && now - musicStoppedAt < 5 * 60000 && !!player)

  // ---- gaming: focused window, re-read on Hyprland focus/fullscreen events ----
  property bool gameRaw: false
  property string gameClass: ""
  // Debounced: entering needs 2 s of a focused fullscreen game, leaving 30 s
  // without one, so alt-tabbing doesn't flap the mode.
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

  readonly property bool eveningNow: {
    const h = new Date(now).getHours(), c = config["evening"];
    return h >= Number(c.from) || h < Number(c.until);
  }

  // ---- the mode ----
  function active(m) {
    if (m === "gaming") return gameNow;
    if (m === "class") return !!classNow;
    if (m === "deep_work") return pomoNow || !!focusBlockNow;
    if (m === "printing") return printingNow;
    if (m === "music") return musicNow;
    if (m === "evening") return eveningNow;
    return m === "morning";
  }
  readonly property string inferred: {
    for (const m of order) if ((m === "morning" || on(m)) && active(m)) return m;
    return "morning";
  }

  // override: {mode, keep: "event"|"hour"|"forever", from (inferred when set), until (ms)}
  property var override: null
  property string keep: "event"   // the menu's current choice for the next pick
  onInferredChanged: if (override && override.keep === "event" && inferred !== override.from) setOverride(null)
  Timer {
    interval: 15000; repeat: true
    running: !!modes.override && modes.override.keep === "hour"
    onTriggered: if (Date.now() >= modes.override.until) modes.setOverride(null)
  }
  function setOverride(o) {
    override = o;
    ofile.setText(JSON.stringify(o && o.keep !== "event" ? o : {}));
  }
  // "auto" | a mode name. Uses `keep` for how long it holds.
  function set(m) {
    if (m === "auto" || !info[m]) { setOverride(null); return; }
    setOverride({ mode: m, keep: keep, from: inferred, until: keep === "hour" ? Date.now() + 3600000 : 0 });
  }
  FileView {
    id: ofile
    path: modes.dataDir + "/modes.json"
    printErrors: false
    onLoaded: {
      try {
        const o = JSON.parse(text());
        if (o && o.mode && modes.info[o.mode] && (o.keep === "forever" || (o.keep === "hour" && o.until > Date.now())))
          modes.override = o;
      } catch (e) {}
    }
  }

  readonly property string mode: override ? override.mode : inferred
  // Desktop cards this mode always shows: by default the ones its layout puts on
  // the desktop (the Desktop Board's recipe, desktop/Layout.js); settings.toml
  // [modes.<name>] pinned = [...] replaces that list ([] for none). DeskState
  // un-minimizes them each time the mode begins.
  readonly property var pinnedCards: {
    const c = config[mode];
    return c && Array.isArray(c.pinned) ? c.pinned.map(String) : DeskLayout.recipeCards(mode);
  }
  readonly property bool manual: !!override
  readonly property bool dnd: !!(config[mode] && config[mode].dnd)
  readonly property string label: mode === "morning" && new Date(now).getHours() >= 12 ? "default" : info[mode].label
  // Why this mode: "COMP348 Lecture 14:00–15:15", "pomodoro running", ...
  readonly property string why: whyOf(mode)
  function whyOf(m) {
    if (m === "gaming") return gameNow ? "fullscreen · " + gameClass : "";
    if (m === "class") return classNow ? classNow.title + " " + hhmm(classNow.start) + "–" + hhmm(classNow.end) : "";
    if (m === "deep_work") return pomoRunning ? "pomodoro running" : pomoNow ? "pomodoro break" : focusBlockNow ? "calendar: " + focusBlockNow.title : "";
    if (m === "printing") return printerWhy;
    if (m === "music") return musicNow && player ? (player.trackTitle || "playing") + (player.trackArtist ? " — " + player.trackArtist : "") : "";
    if (m === "evening") return "after " + String(config["evening"].from).padStart(2, "0") + ":00";
    return new Date(now).getHours() < 12 ? "before 12:00" : "nothing else on";
  }
  function labelOf(m) { return m === "morning" && new Date(now).getHours() >= 12 ? "default" : info[m].label; }
  // The chip's tail: "auto", or how long the pick holds.
  readonly property string holdText: !override ? "auto"
    : override.keep === "hour" ? "until " + hhmm(override.until)
    : override.keep === "forever" ? "until you change it" : "until things change"

  // Kept for the launcher / step-2 callers.
  readonly property string detail: why

  // Mode menu (desktop chip, `M`): open on one screen at a time.
  property bool menuOpen: false

  IpcHandler {
    target: "modes"
    function set(m: string): void { modes.set(m); }
    function get(): string { return modes.mode + (modes.manual ? " (" + modes.holdText + ")" : "") + (modes.why ? " · " + modes.why : ""); }
    function menu(): void { modes.menuOpen = !modes.menuOpen; }
  }
}

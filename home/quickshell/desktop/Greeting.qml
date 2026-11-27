import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."
import "../widgets"
import "../services"
import "../island/Parts.js" as P
import "data"

// The greeting (Desktop Board "Morning greeting"): the first unlock of the day
// (the day starts at 04:00) says "Good morning, Joel." with a line of what
// matters today, and each part of that line flies into the card it belongs to
// while the cards fade in: the greeting becomes the desktop. Holds ~3 s so it
// can be read (holdMs); any key or click skips it. Landing on windows instead, it's a 5 s glance on the pill,
// and the desktop still gets the full greeting the next time it's revealed, if
// that's before 12:00.
//
// Triggers: the shell starting (login), and the lock telling us it unlocked
// (lock/Lock.qml -> `ipc call greeting unlocked`).
// `quickshell ipc ... call greeting test morning|afternoon|evening|free|glance` replays it.
Scope {
  id: g
  property var screen: null
  readonly property var deskOpen: (screen && DeskState.open[screen.name]) || ({})
  readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
  readonly property bool emptyWs: !!(monitor && monitor.activeWorkspace && monitor.activeWorkspace.toplevels.values.length === 0)
  readonly property bool candy: !Globals.eyeCandyOff

  // ---- who ----
  property string name: ""
  Process {
    running: true
    command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
    stdout: StdioCollector {
      onStreamFinished: {
        const full = text.trim(), u = Quickshell.env("USER") || "";
        // "JoelSGC" -> "Joel", "Joel Smith" -> "Joel"
        const m = full.match(/^[A-Z][a-z]+/) || full.match(/^\S+/);
        g.name = m ? m[0] : (u.charAt(0).toUpperCase() + u.slice(1));
      }
    }
  }

  // ---- once a day ----
  readonly property string dataDir: Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")
  property string lastDay: ""
  property bool loaded: false
  function dayKey() { return CalendarData.dkey(new Date(Date.now() - 4 * 3600000)); }
  FileView {
    id: file
    path: g.dataDir + "/greeting.json"
    printErrors: false
    onLoaded: {
      try { const j = JSON.parse(text()); g.lastDay = j.lastDay || ""; g.lastSeen = j.lastSeen || 0; } catch (e) {}
      g.loaded = true;
    }
    onLoadFailed: g.loaded = true
  }
  // When the session was last in use: set on lock, and every 5 min while
  // unlocked. Timers don't run during suspend, so a suspend shows as time away.
  property real lastSeen: 0
  property bool locked: false
  readonly property real awayMs: 4 * 3600000
  function save() { file.setText(JSON.stringify({ lastDay: lastDay, lastSeen: lastSeen })); }
  Timer {
    interval: 5 * 60000; repeat: true
    running: g.loaded && !g.locked
    onTriggered: { g.lastSeen = Date.now(); g.save(); }
  }

  property bool pendingDesk: false
  // Greet on the first unlock of the day, or after 4+ hours away.
  function maybeGreet() {
    if (!loaded) return;
    const newDay = lastDay !== dayKey(), away = lastSeen > 0 && Date.now() - lastSeen >= awayMs;
    lastSeen = Date.now();
    if (newDay || away) {
      lastDay = dayKey();
      save();
      greet(variantNow(), false);
    } else save();
  }
  // A real start (login), not a hot reload: PersistentProperties survive reloads
  // but not restarts. (Reloads used to count, and used up the day's greeting.)
  PersistentProperties {
    id: life
    reloadableId: "greeting-life"
    property bool started: false
  }
  // Give the weather, calendar and printer a moment to load after a login.
  Timer {
    id: startDelay; interval: 2500; running: true
    onTriggered: {
      // The login intro (SessionIntro.qml) first; then the greeting takes over.
      if (DeskState.introActive) { interval = 150; restart(); return; }
      if (!life.started) { life.started = true; g.maybeGreet(); }
    }
  }
  // While the login intro plays, keep the cards hidden if the greeting is going
  // to want them hidden anyway, so they don't appear and vanish again.
  function due() { return loaded && (lastDay !== dayKey() || (lastSeen > 0 && Date.now() - lastSeen >= awayMs)); }
  function holdCards() { if (!life.started && DeskState.introActive && emptyWs && due()) DeskState.greetPhase = 1; }
  onLoadedChanged: holdCards()
  Connections {
    target: DeskState
    function onIntroActiveChanged() { g.holdCards(); }
  }
  onEmptyWsChanged: if (emptyWs && pendingDesk && new Date().getHours() < 12 && new Date().getHours() >= 4) { pendingDesk = false; play(compose(variantNow())); }

  IpcHandler {
    target: "greeting"
    function unlocked(): void { g.locked = false; g.maybeGreet(); }
    function locked(): void { g.locked = true; g.lastSeen = Date.now(); g.save(); }
    function test(variant: string): void {
      if (variant === "glance") g.greet(g.variantNow(), true);
      else g.play(g.compose(variant || g.variantNow()));
    }
  }

  // ---- what to say ----
  function variantNow() {
    const h = new Date().getHours();
    return h < 12 && h >= 4 ? (NextData.free ? "free" : "morning") : h < 19 && h >= 4 ? "afternoon" : "evening";
  }
  function hm(ms) { return Qt.formatDateTime(new Date(ms), "hh:mm"); }
  function weatherSeg() {
    return WeatherData.loaded ? { text: WeatherData.cv(WeatherData.tempC) + "° and " + WeatherData.label(WeatherData.code), color: Pal.yellow, card: "weather" } : null;
  }
  // {title, icon, segs: [{text, color, card}]} -- each segment flies to `card`.
  function compose(variant) {
    const nd = NextData, segs = [];
    const part = variant === "free" ? "morning" : variant;
    if (variant === "morning" || variant === "free") {
      const classes = nd.today.filter(e => e.isClass), evs = classes.length ? classes : nd.today;
      if (evs.length) segs.push({ text: evs.length + (classes.length ? (evs.length === 1 ? " class" : " classes") : (evs.length === 1 ? " event" : " events"))
                                   + " today, first at " + hm(evs[0].start), color: Pal.blue, card: "next" });
      else segs.push({ text: "nothing on the calendar", color: Pal.muted, card: "next" });
      if (Printer.status === "printing" && Printer.remainingMin > 0) segs.push({ text: "print finishes " + hm(Date.now() + Printer.remainingMin * 60000), color: Pal.cyan, card: "printer" });
      else { const todo = KanbanData.cardsOf(0).length; if (todo) segs.push({ text: todo + (todo === 1 ? " kanban to-do" : " kanban to-dos"), color: Pal.green, card: "kanban" }); }
    } else if (variant === "afternoon") {
      const n = nd.later.find(e => nd.daysFrom(e.start) === 0);
      segs.push(n ? { text: n.title + " at " + hm(n.start), color: Pal.yellow, card: "next" } : { text: "nothing left today", color: Pal.muted, card: "next" });
      if (Printer.status === "printing" && Printer.remainingMin > 0) segs.push({ text: "print finishes " + hm(Date.now() + Printer.remainingMin * 60000), color: Pal.cyan, card: "printer" });
      else if (KanbanData.doingCount) segs.push({ text: KanbanData.doingCount + " doing on the kanban", color: Pal.green, card: "kanban" });
    } else {
      const left = nd.later.filter(e => nd.daysFrom(e.start) === 0).length;
      segs.push({ text: left ? left + " left today" : "nothing left today", color: Pal.muted, card: "next" });
      if (nd.tomorrowFirst) segs.push({ text: "tomorrow: " + nd.tomorrowFirst.title + " " + hm(nd.tomorrowFirst.start), color: Pal.purple, card: "next" });
      if (PomodoroData.doneToday) segs.push({ text: PomodoroData.doneToday + (PomodoroData.doneToday === 1 ? " pomodoro" : " pomodoros"), color: Pal.red, card: "pomo" });
    }
    const w = weatherSeg();
    if (w && segs.length < 3) segs.push(w);
    return { title: "Good " + part + (name ? ", " + name : "") + ".", icon: part === "morning" ? "sun-horizon" : part === "afternoon" ? "sun" : "moon-stars", segs: segs.slice(0, 3) };
  }

  // On the desktop, or as a glance on the pill when windows are open.
  function greet(variant, forceGlance) {
    const c = compose(variant);
    if (emptyWs && !forceGlance) { play(c); return; }
    if (!playing) DeskState.greetPhase = 0;   // in case the login intro held the cards
    DeskState.greetGlance([P.icon(c.icon, P.C.ye, 14), P.text(c.title.replace(/\.$/, "")),
                           P.muted("· " + c.segs.map(s => s.text).join(" · "), 13, 900)]);
    pendingDesk = new Date().getHours() < 12;
  }

  // ---- the full greeting ----
  property var content: ({ title: "", segs: [] })
  // How long both lines stay up before flying into the cards.
  property int holdMs: 3200
  property bool playing: false
  property int stage: 0   // 1 lines in · 2 flying · 3 dissolving
  function play(c) {
    tl.stop();
    content = c;
    stage = 0;
    playing = true;
    DeskState.greetPhase = 1;
    if (!candy) { stillTimer.restart(); return; }
    tl.restart();
  }
  function finish() {
    tl.stop(); stillTimer.stop();
    stage = 0;
    playing = false;
    DeskState.greetPhase = 0;
  }
  // Any key or click: everything still moving jumps to its end in one quick fade.
  function skip() {
    if (!playing) return;
    tl.stop();
    DeskState.greetPhase = 0;
    skipFade.restart();
  }
  Timer { id: stillTimer; interval: g.holdMs + 300; onTriggered: g.finish() }

  SequentialAnimation {
    id: tl
    ScriptAction { script: g.stage = 1 }               // 0: line 1 in, line 2 at +120
    // Hold long enough to read (the board's 600 ms was too quick to take in).
    PauseAnimation { duration: g.holdMs }
    ScriptAction { script: { overlay.launch(); g.stage = 2; DeskState.greetPhase = 2; } }
    PauseAnimation { duration: 300 + 40 * Math.max(0, g.content.segs.length - 1) }
    ScriptAction { script: g.stage = 3 }               // segments dissolve into their cards
    PauseAnimation { duration: 150 }
    ScriptAction { script: DeskState.greetPhase = 3 }  // shelf and mode chip
    PauseAnimation { duration: 180 }
    ScriptAction { script: g.finish() }
  }
  NumberAnimation { id: skipFade; target: overlayRoot; property: "opacity"; from: 1; to: 0; duration: 120; onFinished: { g.finish(); overlayRoot.opacity = 1; } }

  PanelWindow {
    id: overlay
    screen: g.screen
    visible: g.playing
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "coel-greeting"
    WlrLayershell.keyboardFocus: g.playing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Where each segment starts (measured from the laid-out line) and lands.
    property var flights: []
    function launch() {
      const out = [];
      for (let i = 0; i < segRepeater.count; i++) {
        const item = segRepeater.itemAt(i), s = g.content.segs[i];
        if (!item || !s) continue;
        const label = item.children[1] || item;   // past the "·" separator
        const p = label.mapToItem(overlayRoot, 0, 0), r = g.deskOpen[s.card];
        out.push({ text: s.text, color: s.color, x0: p.x, y0: p.y, delay: 40 * i,
                   x1: r ? r.x + 18 : p.x, y1: r ? r.y + 40 : p.y, home: !!r });
      }
      flights = out;
    }

    Item {
      id: overlayRoot
      anchors.fill: parent
      focus: true
      Keys.onPressed: (e) => { g.skip(); e.accepted = true; }
      MouseArea { anchors.fill: parent; onClicked: g.skip() }

      // Dim the wallpaper behind the lines so they read on any image; it lifts as
      // the lines fly into the cards.
      Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: g.stage === 1 || (!g.candy && g.playing) ? 0.5 : 0
        Behavior on opacity { enabled: g.candy; NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: P.morph } }
      }

      Mono {
        id: line1
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.36 + (g.stage >= 1 || !g.candy ? 0 : 8)
        text: g.content.title
        font.pixelSize: 64; font.weight: Font.Medium; font.letterSpacing: -1.3
        color: Pal.fg
        opacity: !g.candy ? 1 : g.stage === 1 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: g.stage >= 2 ? 200 : 200; easing.type: Easing.BezierSpline; easing.bezierCurve: g.stage >= 2 ? P.exit : P.enter } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: P.enter } }
      }
      Row {
        id: line2
        anchors.horizontalCenter: parent.horizontalCenter
        y: line1.y + line1.height + 22 + (g.stage >= 1 || !g.candy ? 0 : 8)
        spacing: 18
        visible: g.stage < 2
        opacity: !g.candy ? 1 : g.stage === 1 ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: 120 } NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: P.enter } } }
        Repeater {
          id: segRepeater
          model: g.content.segs.length
          Row {
            required property int index
            spacing: 18
            Mono { visible: parent.index > 0; text: "·"; color: Pal.muted; font.pixelSize: 26 }
            Mono { text: g.content.segs[parent.index] ? g.content.segs[parent.index].text : ""; color: g.content.segs[parent.index] ? g.content.segs[parent.index].color : Pal.fg; font.pixelSize: 26 }
          }
        }
      }
      // The flying segments: x, y and font size together, 300 ms on the morph curve.
      Repeater {
        model: g.stage >= 2 ? overlay.flights : []
        Mono {
          id: fl
          required property var modelData
          property real t: 0
          x: modelData.x0 + (modelData.x1 - modelData.x0) * t
          y: modelData.y0 + (modelData.y1 - modelData.y0) * t
          text: modelData.text
          color: modelData.color
          font.pixelSize: Math.round(26 + (13 - 26) * (modelData.home ? t : 0))
          opacity: g.stage === 3 ? 0 : (modelData.home ? 1 : 1 - t)
          Behavior on opacity { NumberAnimation { duration: 120 } }
          SequentialAnimation {
            running: true
            PauseAnimation { duration: fl.modelData.delay }
            NumberAnimation { target: fl; property: "t"; from: 0; to: 1; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: P.morph }
          }
        }
      }
    }
  }
}

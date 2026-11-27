pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../../widgets"

// The Pomodoro timer: focus / short break / long break, four focus sessions earn
// a long break. "Working on" is a kanban card (doing first, then todo); a
// finished focus session adds one to its `pomos`. State survives reloads in
// pomodoro.json (it stores the end time, not a countdown), which Modes.qml also
// reads for deep-work mode. One copy for every card and monitor, so it alone
// finishes sessions, notifies and answers IPC.
Singleton {
  id: root

  property int focusMin: 25
  property int shortMin: 5
  property int longMin: 15
  property bool autoStart: false

  property string mode: "focus"        // focus | short | long
  property real frozen: -1             // seconds frozen by pause; -1 = untouched
  property bool running: false
  property real endAt: 0
  property real nowMs: Date.now()
  property int cycle: 0                // focus sessions finished, for the 4-set
  property int doneToday: 0
  property int minsToday: 0
  property string day: dayKey()
  property int taskId: -1
  property string flash: ""

  function dayKey() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }
  function dur(m) { return 60 * (m === "focus" ? focusMin : m === "short" ? shortMin : longMin); }
  function fmt(x) { return String(Math.floor(x / 60)).padStart(2, "0") + ":" + String(x % 60).padStart(2, "0"); }

  readonly property int modeDur: dur(mode)
  readonly property int secsLeft: running ? Math.max(0, Math.ceil((endAt - nowMs) / 1000)) : (frozen >= 0 ? frozen : modeDur)
  readonly property real progress: modeDur > 0 ? secsLeft / modeDur : 0
  readonly property bool paused: !running && frozen >= 0 && frozen < modeDur
  readonly property string stateName: running ? "running" : paused ? "paused" : "ready"
  readonly property var modeColors: ({ focus: Pal.red, short: Pal.green, long: Pal.blue })
  readonly property var modeNames: ({ focus: "focus", short: "short break", long: "long break" })
  readonly property color modeColor: modeColors[mode]
  readonly property string modeName: modeNames[mode]
  readonly property int session: (cycle % 4) + 1
  readonly property int filled: cycle % 4 === 0 && cycle > 0 && mode === "long" ? 4 : cycle % 4
  readonly property string btnLabel: running ? "pause" : paused ? "resume" : "start"
  readonly property string todayText: doneToday + " today · " + (minsToday >= 60 ? Math.floor(minsToday / 60) + "h " + (minsToday % 60) + "m" : minsToday + "m")
  // "▶ 18:42 focus" (minimized card)
  readonly property string summary: (running ? "▶" : paused ? "❚❚" : "·") + " " + fmt(secsLeft) + " " + modeName

  // ----- kanban link -----
  readonly property var tasks: KanbanData.cardsOf(1).concat(KanbanData.cardsOf(0))
  readonly property var task: {
    for (const t of tasks) if (t.id === taskId) return t;
    return null;
  }
  function nextTask() {
    const ids = tasks.map(t => t.id).concat([-1]);
    taskId = ids[(ids.indexOf(taskId) + 1) % ids.length];
    save();
  }

  // ----- actions -----
  function toggle() {
    const l = secsLeft;
    if (running) { running = false; frozen = l; }
    else { nowMs = Date.now(); endAt = nowMs + l * 1000; running = true; flash = ""; }
    save();
  }
  function reset() { running = false; frozen = -1; flash = ""; save(); }
  function pick(m) { mode = m; running = false; frozen = -1; flash = ""; save(); }
  function advance(natural) {
    let next, msg;
    if (mode === "focus") {
      if (natural) {
        cycle++; doneToday++; minsToday += focusMin;
        if (taskId !== -1) KanbanData.bumpPomos(taskId);
      }
      next = natural && cycle % 4 === 0 ? "long" : "short";
      msg = natural ? (next === "long" ? "set of four done · long break" : "focus done · take " + shortMin) : "focus skipped";
    } else {
      next = "focus";
      msg = natural ? "break over · back to it" : "break skipped";
    }
    if (natural) notifier.run(msg);
    mode = next;
    flash = msg;
    frozen = -1;
    if (autoStart) { nowMs = Date.now(); endAt = nowMs + dur(next) * 1000; running = true; }
    else running = false;
    save();
  }
  // Keys shared by every pomodoro card size.
  function handleKey(e) {
    if (e.key === Qt.Key_Space) toggle();
    else if (e.key === Qt.Key_R) reset();
    else if (e.key === Qt.Key_S || e.key === Qt.Key_N) advance(false);
    else if (e.key === Qt.Key_T) nextTask();
    else return false;
    return true;
  }

  // `quickshell ipc -p ~/.nixos/home/quickshell call pomodoro toggle|reset|skip|status`
  IpcHandler {
    target: "pomodoro"
    function toggle(): void { root.toggle(); }
    function reset(): void { root.reset(); }
    function skip(): void { root.advance(false); }
    function status(): string { return root.stateName + " " + root.modeName + " " + root.fmt(root.secsLeft); }
  }
  Timer {
    interval: 1000
    running: root.running
    repeat: true
    onTriggered: {
      root.nowMs = Date.now();
      if (root.nowMs >= root.endAt) root.advance(true);
    }
  }
  Process {
    id: notifier
    property string body: ""
    function run(msg) { body = msg; running = true; }
    command: ["notify-send", "-a", "pomodoro", "-i", "appointment-soon", "Pomodoro", body]
  }

  // ----- persistence -----
  property bool loaded: false
  property string lastSaved: ""
  function save() {
    if (!loaded) return;
    const text = JSON.stringify({
      mode: mode, left: frozen, running: running, endAt: endAt, cycle: cycle,
      doneToday: doneToday, minsToday: minsToday, day: day, taskId: taskId
    }, null, 2);
    lastSaved = text;
    pfile.setText(text);
  }
  function applyState(j) {
    if (["focus", "short", "long"].indexOf(j.mode) >= 0) mode = j.mode;
    frozen = typeof j.left === "number" ? j.left : -1;
    running = !!j.running;
    endAt = j.endAt || 0;
    cycle = j.cycle || 0;
    taskId = typeof j.taskId === "number" ? j.taskId : -1;
    if (j.day === dayKey()) { doneToday = j.doneToday || 0; minsToday = j.minsToday || 0; }
    day = dayKey();
    nowMs = Date.now();
  }
  FileView {
    id: pfile
    path: KanbanData.dirReady ? KanbanData.dataDir + "/pomodoro.json" : ""
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      const t = text();
      if (root.loaded) {
        if (t === root.lastSaved) return;
        try { root.applyState(JSON.parse(t)); } catch (e) { console.warn("pomodoro: pomodoro.json unreadable:", e); }
        return;
      }
      try { root.applyState(JSON.parse(t)); }
      catch (e) { console.warn("pomodoro: pomodoro.json unreadable, starting fresh:", e); }
      root.loaded = true;
      // it finished while the shell was down
      if (root.running && root.nowMs >= root.endAt) root.advance(true);
    }
    onLoadFailed: root.loaded = true
  }
}

import Quickshell
import Quickshell.Io
import ".."
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// ===== POMODORO WIDGET =====
// Focus / short break / long break timer with a progress ring. Four focus
// sessions earn a long break. "Working on" picks a card from the kanban board
// (doing first, then to do) and a finished focus session adds one to that
// card's `pomos` count in kanban.json -- the board shows it as a small tally.
//
// State survives a shell reload in pomodoro.json next to kanban.json (the
// timer keeps running across it: it stores the end time, not a countdown).
// The finished-session notification goes through notify-send, i.e. the
// shell's own notification server.
WidgetCard {
  id: root

  property int focusMin: 25
  property int shortMin: 5
  property int longMin: 15
  property bool autoStart: false
  property bool showHints: true

  // ----- timer state -----
  property string mode: "focus"        // focus | short | long
  property real frozen: -1                 // seconds frozen by pause; -1 = untouched
  property bool running: false
  property real endAt: 0
  property real nowMs: Date.now()
  property int cycle: 0                  // focus sessions finished, for the 4-set
  property int doneToday: 0
  property int minsToday: 0
  property string day: dayKey()
  property int taskId: -1
  property string flash: ""

  widgetId: "pomodoro"
  title: "pomodoro"
  cardWidth: 340
  summary: (running ? "▶" : paused ? "❚❚" : "·") + " " + fmt(secsLeft) + " " + modeName

  function dayKey() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }
  function dur(m) { return 60 * (m === "focus" ? focusMin : m === "short" ? shortMin : longMin); }
  function fmt(x) { return String(Math.floor(x / 60)).padStart(2, "0") + ":" + String(x % 60).padStart(2, "0"); }

  readonly property int modeDur: dur(mode)
  readonly property int secsLeft: running ? Math.max(0, Math.ceil((endAt - nowMs) / 1000)) : (frozen >= 0 ? frozen : modeDur)
  readonly property bool paused: !running && frozen >= 0 && frozen < modeDur
  readonly property string stateName: running ? "running" : paused ? "paused" : "ready"
  readonly property var modeColors: ({ focus: Pal.red, short: Pal.green, long: Pal.blue })
  readonly property var modeNames: ({ focus: "focus", short: "short break", long: "long break" })
  readonly property color modeColor: modeColors[mode]
  readonly property string modeName: modeNames[mode]
  readonly property int filled: cycle % 4 === 0 && cycle > 0 && mode === "long" ? 4 : cycle % 4
  readonly property string btnLabel: running ? "pause" : paused ? "resume" : "start"

  // ----- kanban link -----
  property string kanbanText: ""
  readonly property var tasks: {
    let j;
    try { j = JSON.parse(kanbanText); } catch (e) { return []; }
    if (!j || !Array.isArray(j.columns) || j.columns.length < 2) return [];
    return (j.columns[1].cards || []).concat(j.columns[0].cards || []);
  }
  readonly property var task: {
    for (const t of tasks) if (t.id === taskId) return t;
    return null;
  }

  function nextTask() {
    const ids = tasks.map(function (t) { return t.id; }).concat([-1]);
    const i = ids.indexOf(taskId);
    taskId = ids[(i + 1) % ids.length];
    save();
  }
  function bumpPomos(id) {
    let j;
    try { j = JSON.parse(kanbanText); } catch (e) { return; }
    let hit = false;
    for (const col of j.columns || []) for (const c of col.cards || []) {
      if (c.id === id) { c.pomos = (c.pomos || 0) + 1; hit = true; }
    }
    if (!hit) return;
    kanbanText = JSON.stringify(j, null, 2);
    kfile.setText(kanbanText);
  }

  // ----- actions -----
  function toggle() {
    if (running) {
      const l = secsLeft;
      running = false;
      frozen = l;
    } else {
      const l = secsLeft;
      nowMs = Date.now();
      endAt = nowMs + l * 1000;
      running = true;
      flash = "";
    }
    save();
  }
  function reset() { running = false; frozen = -1; flash = ""; save(); }
  function pick(m) { mode = m; running = false; frozen = -1; flash = ""; save(); }
  function advance(natural) {
    let next, msg;
    if (mode === "focus") {
      if (natural) {
        cycle++; doneToday++; minsToday += focusMin;
        if (taskId !== -1) bumpPomos(taskId);
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

  onKeyPressed: (e) => {
    let used = true;
    if (e.key === Qt.Key_Space) toggle();
    else if (e.key === Qt.Key_R) reset();
    else if (e.key === Qt.Key_N) advance(false);
    else if (e.key === Qt.Key_T) nextTask();
    else used = false;
    e.accepted = used;
  }

  // `quickshell ipc -p ~/.nixos/home/quickshell call pomodoro toggle|reset|skip`
  // -- for keybinds, and handy for poking the timer without the mouse.
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
  FileView {
    id: pfile
    path: WidgetState.dirReady ? WidgetState.dataDir + "/pomodoro.json" : ""
    onLoaded: {
      if (root.loaded) return;
      try {
        const j = JSON.parse(text());
        if (["focus", "short", "long"].indexOf(j.mode) >= 0) root.mode = j.mode;
        root.frozen = typeof j.left === "number" ? j.left : -1;
        root.running = !!j.running;
        root.endAt = j.endAt || 0;
        root.cycle = j.cycle || 0;
        root.taskId = typeof j.taskId === "number" ? j.taskId : -1;
        if (j.day === root.dayKey()) { root.doneToday = j.doneToday || 0; root.minsToday = j.minsToday || 0; }
        root.day = root.dayKey();
      } catch (e) {
        console.warn("pomodoro: pomodoro.json unreadable, starting fresh:", e);
      }
      root.loaded = true;
      root.nowMs = Date.now();
      // it finished while the shell was down
      if (root.running && root.nowMs >= root.endAt) root.advance(true);
    }
    onLoadFailed: root.loaded = true
  }
  FileView {
    id: kfile
    path: WidgetState.dirReady ? WidgetState.dataDir + "/kanban.json" : ""
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.kanbanText = text()
  }

  // ----- timer + modes -----
  Box {
    Layout.fillWidth: true
    padTop: 16; padSide: 12; padBottom: 12
    legend: root.mode === "focus" ? "session " + ((root.cycle % 4) + 1) + " of 4" : "break"
    rightLegend: root.stateName
    rightColor: root.running ? root.modeColor : root.paused ? Pal.yellow : Pal.muted

    RowLayout {
      Layout.fillWidth: true
      spacing: 16

      Item {
        Layout.preferredWidth: 112; Layout.preferredHeight: 112
        Layout.alignment: Qt.AlignVCenter

        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: Pal.track; strokeWidth: 5; fillColor: "transparent"
            PathAngleArc { centerX: 56; centerY: 56; radiusX: 53.5; radiusY: 53.5; startAngle: 0; sweepAngle: 360 }
          }
          ShapePath {
            strokeColor: root.modeColor; strokeWidth: 5; fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
              centerX: 56; centerY: 56; radiusX: 53.5; radiusY: 53.5
              startAngle: -90
              sweepAngle: root.modeDur > 0 ? 359.9 * root.secsLeft / root.modeDur : 0
            }
          }
        }
        ColumnLayout {
          anchors.centerIn: parent
          spacing: 2
          Mono {
            Layout.alignment: Qt.AlignHCenter
            text: root.fmt(root.secsLeft)
            font.pixelSize: 24; font.weight: Font.Medium
          }
          Mono {
            Layout.alignment: Qt.AlignHCenter
            text: root.running ? "▶ " + root.modeName : root.paused ? "❚❚ paused" : root.modeName
            font.pixelSize: 11; color: root.modeColor
          }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggle()
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Repeater {
          model: ["focus", "short", "long"]
          delegate: Rectangle {
            id: opt
            required property string modelData
            readonly property bool sel: root.mode === modelData
            Layout.fillWidth: true
            implicitHeight: optRow.implicitHeight
            radius: Globals.eyeCandyOff ? 0 : 2
            color: sel ? Pal.edge : (optArea.containsMouse ? Pal.edge : "transparent")
            RowLayout {
              id: optRow
              anchors { left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
              spacing: 6
              Mono { text: opt.sel ? "(•)" : "( )"; color: opt.sel ? root.modeColors[opt.modelData] : Pal.muted }
              Mono { Layout.fillWidth: true; text: opt.modelData; color: opt.sel ? Pal.fg : Pal.dim }
              Mono { text: root.dur(opt.modelData) / 60 + "m"; color: Pal.muted }
            }
            MouseArea {
              id: optArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.pick(opt.modelData)
            }
          }
        }

        RowLayout {
          Layout.topMargin: 8
          Layout.leftMargin: 6
          spacing: 6
          Repeater {
            model: 4
            delegate: Rectangle {
              required property int index
              width: 8; height: 8; radius: Globals.eyeCandyOff ? 0 : 4
              color: index < root.filled ? Pal.red : Pal.faint
            }
          }
          Mono {
            Layout.leftMargin: 4
            text: root.doneToday + " today · " + (Math.floor(root.minsToday / 60) > 0 ? Math.floor(root.minsToday / 60) + "h " : "") + (root.minsToday % 60) + "m"
            color: Pal.muted
          }
        }
      }
    }

    Mono {
      visible: root.flash !== ""
      Layout.topMargin: 10
      text: "→ " + root.flash
      color: root.modeColor
    }
  }

  // ----- task -----
  Box {
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 12; padSide: 6; padBottom: 6
    legend: "working on"
    rightLegend: "from kanban"

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: taskRow.implicitHeight + 2
      radius: Globals.eyeCandyOff ? 0 : 2
      color: taskArea.containsMouse ? Pal.edge : "transparent"
      RowLayout {
        id: taskRow
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
        spacing: 8
        Mono { text: "⇅"; color: Pal.muted }
        Mono {
          Layout.fillWidth: true
          text: root.task ? root.task.title : "no task"
          color: root.task ? Pal.fg : Pal.muted
          elide: Text.ElideRight
        }
        Mono { visible: !!(root.task && root.task.tag); text: root.task && root.task.tag ? "#" + root.task.tag : ""; font.pixelSize: 11; color: Pal.cyan }
        Mono { visible: !!(root.task && root.task.pomos); text: root.task && root.task.pomos ? "◷ " + root.task.pomos : ""; font.pixelSize: 11; color: Pal.red }
      }
      MouseArea {
        id: taskArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.nextTask()
      }
    }
  }

  // ----- controls -----
  Hints {
    visible: root.showHints
    Layout.fillWidth: true
    Layout.topMargin: 14
    items: [["space", root.btnLabel], ["r", "reset"], ["n", "skip"], ["t", "task"]]
  }
  RowLayout {
    Layout.fillWidth: true
    Layout.topMargin: root.showHints ? 8 : 14
    spacing: 4

    Item { Layout.fillWidth: true }
    TextButton {
      onClicked: root.reset()
      Mono { text: "[reset]"; color: Pal.dim }
    }
    TextButton {
      onClicked: root.advance(false)
      Mono { text: "[skip ›]"; color: Pal.dim }
    }
    Rectangle {
      implicitWidth: goText.implicitWidth + 20
      implicitHeight: goText.implicitHeight + 2
      radius: Globals.eyeCandyOff ? 0 : 2
      color: root.running ? Pal.yellow : root.modeColor
      Mono { id: goText; anchors.centerIn: parent; text: "< " + root.btnLabel + " >"; font.weight: Font.Medium; color: Pal.card }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
      }
    }
  }
}

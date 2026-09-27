import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import QtQuick.LocalStorage

import "../components"

// ===== CALENDAR DROPDOWN =====
// Rebuilt to match "Quickshell Example/Quickshell Bar.dc.html"'s actual
// calendar mock exactly (calVals()/calKey() in that file), after an
// earlier from-scratch attempt drifted from it. Structure/behavior below
// is a direct port of that mock's logic, not a fresh design.
//
// Todos persist in a real SQLite database via QtQuick.LocalStorage
// (bundled with Qt, no extra packaging needed) rather than the mock's
// own localStorage -- picked over a flat JSON file specifically with an
// eye on a possible future Google Calendar/ICS sync: that would need
// real indexed date-range queries and per-source sync state (calendar
// id, etags, recurrence rules), which is what a relational store is
// actually for. None of that exists yet -- this is deliberately just a
// `todos` table matching today's data, not a schema speculatively built
// out for a feature that isn't being built right now.
//
// `todos` (the in-memory `{dateKey: [items]}` object every render/
// keyboard function below already reads/writes) stays exactly as it was
// -- it's now a cache hydrated from SQLite once at startup, kept in
// sync by mirroring every mutation into both places, rather than every
// render path querying the database directly.
Item {
  id: dropdownRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  property bool popupOpen: false

  signal closeRequested()

  // ----- live clock -----
  property var now: new Date()
  Timer {
    interval: 1000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: dropdownRoot.now = new Date()
  }

  function dkey(d) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }

  // ----- todos -----
  // Keyed by dkey(date) -> array of { id, t: "HH:MM"|"", text, done }.
  // `id` is the real SQLite row id now (assigned by the DB on insert),
  // not a locally-incremented counter.
  property var todos: ({})
  property var db: null

  function openDb() {
    return LocalStorage.openDatabaseSync(
      "CoelOSCalendarTodos", "1.0",
      "Local todos for the CoelOS quickshell calendar dropdown", 1000000);
  }
  function dbEnsureSchema() {
    db.transaction(function (tx) {
      tx.executeSql("CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, time TEXT NOT NULL DEFAULT '', text TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0)");
      tx.executeSql("CREATE INDEX IF NOT EXISTS idx_todos_date ON todos(date)");
    });
  }
  function loadTodos() {
    const out = {};
    db.transaction(function (tx) {
      const rs = tx.executeSql("SELECT id, date, time, text, done FROM todos ORDER BY date ASC, (time = '') ASC, time ASC");
      for (let i = 0; i < rs.rows.length; i++) {
        const r = rs.rows.item(i);
        if (!out[r.date]) out[r.date] = [];
        out[r.date].push({ id: r.id, t: r.time, text: r.text, done: r.done === 1 });
      }
    });
    todos = out;
  }
  Component.onCompleted: {
    tzProc.running = true;
    dropdownRoot.db = dropdownRoot.openDb();
    dropdownRoot.dbEnsureSchema();
    dropdownRoot.loadTodos();
  }

  property string calSel: dkey(now)
  property int calY: now.getFullYear()
  property int calM: now.getMonth()
  property string calFocus: "cal" // "cal" | "todo"
  property int tdSel: 0
  property string tdDraft: ""
  readonly property bool todoFocused: calFocus === "todo"

  function calSelDate() {
    const p = calSel.split("-").map(Number);
    return new Date(p[0], p[1] - 1, p[2]);
  }
  function calSetSel(d) {
    calSel = dkey(d);
    calY = d.getFullYear();
    calM = d.getMonth();
    tdSel = 0;
  }
  function jumpToToday() { calSetSel(new Date()); }
  // Walks the *selected* date to the same day-of-month (clamped to 28,
  // same as the mock) in the previous/next month -- not just sliding the
  // displayed grid while leaving the selection where it was.
  function calPrev() {
    const sel = calSelDate();
    calSetSel(new Date(calY, calM - 1, Math.min(sel.getDate(), 28)));
  }
  function calNext() {
    const sel = calSelDate();
    calSetSel(new Date(calY, calM + 1, Math.min(sel.getDate(), 28)));
  }

  function tdList() { return todos[calSel] || []; }
  function tdUpdate(fn) {
    const next = Object.assign({}, todos);
    next[calSel] = fn(todos[calSel] || []);
    todos = next;
  }
  function toggleTodoAt(i) {
    const list = tdList();
    if (i < 0 || i >= list.length) return;
    const item = list[i];
    const newDone = !item.done;
    db.transaction(function (tx) {
      tx.executeSql("UPDATE todos SET done = ? WHERE id = ?", [newDone ? 1 : 0, item.id]);
    });
    tdUpdate(l => l.map((x, j) => j === i ? Object.assign({}, x, { done: newDone }) : x));
  }
  function deleteTodoAt(i) {
    const list = tdList();
    if (i < 0 || i >= list.length) return;
    const item = list[i];
    db.transaction(function (tx) {
      tx.executeSql("DELETE FROM todos WHERE id = ?", [item.id]);
    });
    tdUpdate(l => l.filter((_, j) => j !== i));
  }
  function addTodo() {
    const raw = tdDraft.trim();
    if (!raw) return;
    const m = raw.match(/^(\d{1,2}):(\d{2})\s+(.+)$/);
    const t = m ? (m[1].padStart(2, "0") + ":" + m[2]) : "";
    const text = m ? m[3] : raw;
    let newId = -1;
    db.transaction(function (tx) {
      newId = tx.executeSql("INSERT INTO todos (date, time, text, done) VALUES (?, ?, ?, 0)", [calSel, t, text]).insertId;
    });
    const item = { id: newId, t, text, done: false };
    tdUpdate(l => l.concat([item]).sort((a, b) => {
      const at = a.t.length > 0 ? a.t : "99", bt = b.t.length > 0 ? b.t : "99";
      return at < bt ? -1 : at > bt ? 1 : 0;
    }));
    tdDraft = "";
  }

  // ----- block/dot-matrix digit clock -----
  // Each digit is a 3-wide x 5-tall bitmap (row-major, 15 chars), same
  // table as the mock's own F[] -- standard 3x5 dot-matrix glyphs.
  readonly property var digitBits: ({
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
    "3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
    "6": "111100111101111", "7": "111001001001001", "8": "111101111101111",
    "9": "111101111001111",
  })
  readonly property bool blinkOn: now.getSeconds() % 2 === 0
  readonly property string hourStr: String((now.getHours() % 12) || 12).padStart(2, "0")
  readonly property string minStr: String(now.getMinutes()).padStart(2, "0")
  readonly property var clkGlyphs: [
    { cols: 3, bits: digitBits[hourStr[0]], on: colors[0] },
    { cols: 3, bits: digitBits[hourStr[1]], on: colors[0] },
    { cols: 1, bits: "01010", on: blinkOn ? colors[0] : hoverColor },
    { cols: 3, bits: digitBits[minStr[0]], on: colors[0] },
    { cols: 3, bits: digitBits[minStr[1]], on: colors[0] },
  ]
  readonly property string clkAmpm: now.getHours() < 12 ? "AM" : "PM"
  readonly property string clkSecStr: String(now.getSeconds()).padStart(2, "0")
  readonly property string clkDate: Qt.formatDate(now, "dddd, MMMM d, yyyy")
  readonly property int dayOfYear: {
    const start = new Date(now.getFullYear(), 0, 1);
    return Math.floor((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - start) / 86400000) + 1;
  }
  readonly property bool isLeapYear: new Date(now.getFullYear(), 1, 29).getDate() === 29
  property string tzName: "local"
  Process {
    id: tzProc
    command: ["timedatectl", "show", "--value", "-p", "Timezone"]
    stdout: StdioCollector {
      onStreamFinished: { if (text.trim().length > 0) dropdownRoot.tzName = text.trim(); }
    }
  }
  readonly property string clkMeta: "day " + dayOfYear + "/" + (isLeapYear ? 366 : 365) + " · " + tzName

  // ----- week/status header -----
  function isoWeek(d) {
    const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
    const dn = t.getUTCDay() || 7;
    t.setUTCDate(t.getUTCDate() + 4 - dn);
    const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
    return Math.ceil(((t - y0) / 86400000 + 1) / 7);
  }
  readonly property int calWeek: isoWeek(now)
  readonly property string todayKeyStr: dkey(now)
  readonly property var todayList: todos[todayKeyStr] || []
  readonly property int todayOpenCount: todayList.filter(x => !x.done).length
  readonly property string calStatus: todayOpenCount > 0 ? (todayOpenCount + " open today") : "✓ all done today"
  readonly property color calStatusColor: todayOpenCount > 0 ? colors[2] : colors[3]

  // ----- month grid -----
  readonly property string calMonthLabel: Qt.formatDate(new Date(calY, calM, 1), "MMMM yyyy").toLowerCase()
  readonly property int monthBoxInnerWidth: 268 - 16 // Section width(268) minus paddingSide(8)*2
  readonly property real dayCellWidth: (monthBoxInnerWidth - 6 * 2) / 7 // 7 cols, 6 gaps of 2px
  readonly property color calBorderColor: !todoFocused ? "#4b5263" : hoverColor
  readonly property color calLegendColor: !todoFocused ? colors[0] : mutedColor
  readonly property color tdBorderColor: todoFocused ? "#4b5263" : hoverColor
  readonly property color tdLegendColor: todoFocused ? colors[0] : mutedColor

  readonly property var calCells: {
    const first = new Date(calY, calM, 1);
    const lead = first.getDay(); // days back to the preceding Sunday (getDay() 0 = Sunday)
    const out = [];
    for (let i = 0; i < 42; i++) {
      const d = new Date(calY, calM, 1 - lead + i);
      const k = dkey(d);
      const inMonth = d.getMonth() === calM;
      const isToday = k === todayKeyStr;
      const isSel = k === calSel;
      const list = todos[k] || [];
      const openCount = list.filter(x => !x.done).length;
      const wknd = d.getDay() === 0 || d.getDay() === 6;
      out.push({
        date: d,
        label: d.getDate(),
        weight: isToday ? Font.DemiBold : Font.Normal,
        color: isToday ? "#282c34" : !inMonth ? "#4b5263" : wknd ? mutedColor : fgColor,
        bg: isToday ? colors[0] : isSel ? "#2f343e" : "transparent",
        border: isSel ? (!todoFocused ? colors[2] : mutedColor) : "transparent",
        dot: list.length === 0 ? "transparent" : openCount > 0 ? (isToday ? "#282c34" : colors[2]) : (isToday ? "#282c34" : mutedColor),
      });
    }
    return out;
  }

  // ----- todo panel -----
  readonly property string tdDayLabel: {
    const sel = calSelDate();
    const selMid = new Date(sel.getFullYear(), sel.getMonth(), sel.getDate());
    const nowMid = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const rel = Math.round((selMid - nowMid) / 86400000);
    if (rel === 0) return "today";
    if (rel === 1) return "tomorrow";
    if (rel === -1) return "yesterday";
    return Qt.formatDate(sel, "ddd, MMM d");
  }
  readonly property string nowHM: String(now.getHours()).padStart(2, "0") + ":" + String(now.getMinutes()).padStart(2, "0")
  readonly property var tdRows: {
    const list = tdList();
    const out = [];
    for (let i = 0; i < list.length; i++) {
      const x = list[i];
      const isSel = i === tdSel && todoFocused;
      const overdue = !x.done && x.t.length > 0 && calSel === todayKeyStr && x.t < nowHM;
      out.push({
        idx: i,
        isSel,
        box: x.done ? "[x]" : "[ ]",
        boxColor: x.done ? colors[3] : mutedColor,
        time: x.t,
        timeColor: x.done ? "#4b5263" : overdue ? colors[1] : colors[2],
        text: x.text,
        strike: x.done,
        textColor: x.done ? mutedColor : fgColor,
      });
    }
    return out;
  }
  readonly property int tdDoneCount: tdList().filter(x => x.done).length
  readonly property string tdSummary: tdList().length > 0 ? (tdDoneCount + "/" + tdList().length + " done") : ""

  readonly property var hints: todoFocused
    ? [{ k: "tab", l: "calendar" }, { k: "j/k", l: "move" }, { k: "space", l: "done" }, { k: "x", l: "delete" }, { k: "a", l: "add" }, { k: "esc", l: "close" }]
    : [{ k: "tab", l: "todos" }, { k: "hjkl", l: "day" }, { k: "[ ]", l: "month" }, { k: "t", l: "today" }, { k: "a", l: "add" }, { k: "esc", l: "close" }]

  focus: true
  Keys.onPressed: (event) => {
    if (tdInput.activeFocus) {
      if (event.key === Qt.Key_Escape) { dropdownRoot.forceActiveFocus(); event.accepted = true; }
      return;
    }
    if (event.key === Qt.Key_Escape) { closeRequested(); event.accepted = true; return; }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      calFocus = todoFocused ? "cal" : "todo";
      event.accepted = true;
      return;
    }
    if (event.key === Qt.Key_A) { tdInput.forceActiveFocus(); event.accepted = true; return; }
    if (event.key === Qt.Key_T) { jumpToToday(); event.accepted = true; return; }
    if (event.key === Qt.Key_BracketLeft || (event.key === Qt.Key_H && (event.modifiers & Qt.ShiftModifier))) {
      calPrev(); event.accepted = true; return;
    }
    if (event.key === Qt.Key_BracketRight || (event.key === Qt.Key_L && (event.modifiers & Qt.ShiftModifier))) {
      calNext(); event.accepted = true; return;
    }
    if (!todoFocused) {
      const sel = calSelDate();
      let step = 0;
      switch (event.key) {
        case Qt.Key_H: case Qt.Key_Left: step = -1; break;
        case Qt.Key_L: case Qt.Key_Right: step = 1; break;
        case Qt.Key_K: case Qt.Key_Up: step = -7; break;
        case Qt.Key_J: case Qt.Key_Down: step = 7; break;
      }
      if (step !== 0) {
        calSetSel(new Date(sel.getFullYear(), sel.getMonth(), sel.getDate() + step));
        event.accepted = true;
        return;
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { calFocus = "todo"; event.accepted = true; return; }
      event.accepted = false;
      return;
    }
    const list = tdList();
    const i = Math.min(tdSel, list.length - 1);
    switch (event.key) {
      case Qt.Key_J: case Qt.Key_Down:
        tdSel = Math.min(list.length - 1, i + 1); event.accepted = true; break;
      case Qt.Key_K: case Qt.Key_Up:
        tdSel = Math.max(0, i - 1); event.accepted = true; break;
      case Qt.Key_Space: case Qt.Key_Return: case Qt.Key_Enter:
        if (list.length > 0) toggleTodoAt(i); event.accepted = true; break;
      case Qt.Key_X:
        if (list.length > 0) deleteTodoAt(i); event.accepted = true; break;
      default:
        event.accepted = false;
    }
  }

  implicitWidth: 660
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: 0

    // ----- header -----
    RowLayout {
      width: parent.width
      height: 28

      RowLayout {
        spacing: 8
        Text { text: "calendar"; color: dropdownRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
        Text { text: "─ week " + dropdownRoot.calWeek + " ─"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        Text { text: dropdownRoot.calStatus; color: dropdownRoot.calStatusColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        implicitWidth: todayLabel.implicitWidth + 16
        implicitHeight: 20
        radius: 2
        color: todayMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
        Text {
          id: todayLabel
          anchors.centerIn: parent
          text: "<font color='" + dropdownRoot.colors[2] + "'>t</font> today"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
        MouseArea { id: todayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.jumpToToday() }
      }
      Text {
        text: "[×]"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.closeRequested() }
      }
    }

    Item { width: 1; height: 8 }

    // ----- body: 268px left column (clock + month), flexible right (todos) -----
    Item {
      id: bodyRow
      width: parent.width
      height: Math.max(leftCol.implicitHeight, todoSection.implicitHeight)

      Column {
        id: leftCol
        width: 268
        spacing: 16

        Section {
          width: parent.width
          label: "clock"
          paddingTop: 16
          paddingBottom: 10
          paddingSide: 12
          spacing: 10

          // Manual Item+anchors, not RowLayout -- RowLayout's own
          // cross-axis alignment left the ampm/seconds column sitting
          // roughly mid-height instead of flush with the glyphs' own
          // bottom row, confirmed live. Anchoring straight to glyphRow's
          // bottom sidesteps whatever RowLayout was doing there.
          Item {
            width: parent.width
            height: glyphRow.height

            Row {
              id: glyphRow
              spacing: 6
              Repeater {
                model: dropdownRoot.clkGlyphs
                delegate: Grid {
                  id: glyphCell
                  required property var modelData
                  columns: modelData.cols
                  rowSpacing: 2
                  columnSpacing: 2
                  Repeater {
                    model: glyphCell.modelData.bits.split("")
                    delegate: Rectangle {
                      required property string modelData
                      width: 10
                      height: 10
                      radius: 1
                      color: modelData === "1" ? glyphCell.modelData.on : "transparent"
                    }
                  }
                }
              }
            }

            Column {
              anchors.left: glyphRow.right
              anchors.leftMargin: 10
              anchors.bottom: glyphRow.bottom
              spacing: 0
              Text { text: dropdownRoot.clkAmpm; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              Text { text: ":" + dropdownRoot.clkSecStr; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            }
          }

          Text { width: parent.width; text: dropdownRoot.clkDate; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          Text { width: parent.width; text: dropdownRoot.clkMeta; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        }

        Section {
          width: parent.width
          label: ""
          paddingTop: 14
          paddingBottom: 8
          paddingSide: 8
          spacing: 4
          borderColor: dropdownRoot.calBorderColor

          leftContent: RowLayout {
            spacing: 6
            Text {
              text: "‹"
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 14
              MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.calPrev() }
            }
            Text {
              text: dropdownRoot.calMonthLabel
              color: dropdownRoot.calLegendColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              text: "›"
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 14
              MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.calNext() }
            }
          }

          Grid {
            width: parent.width
            columns: 7
            columnSpacing: 2
            Repeater {
              model: ["su", "mo", "tu", "we", "th", "fr", "sa"]
              delegate: Text {
                required property string modelData
                required property int index
                width: dropdownRoot.dayCellWidth
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: (index === 0 || index === 6) ? dropdownRoot.mutedColor : dropdownRoot.colors[2]
                font.family: "JetBrains Mono"
                font.pixelSize: 11
              }
            }
          }
          Grid {
            width: parent.width
            columns: 7
            columnSpacing: 2
            rowSpacing: 2
            Repeater {
              model: dropdownRoot.calCells
              delegate: Rectangle {
                id: dayCell
                required property var modelData
                width: dropdownRoot.dayCellWidth
                height: 28
                radius: 2
                color: modelData.bg
                border.width: 1
                border.color: modelData.border

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: 4
                  text: String(dayCell.modelData.label)
                  color: dayCell.modelData.color
                  font.family: "JetBrains Mono"
                  font.weight: dayCell.modelData.weight
                  font.pixelSize: 12
                }
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: 20
                  width: 4
                  height: 4
                  radius: 2
                  color: dayCell.modelData.dot
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: dropdownRoot.calSetSel(dayCell.modelData.date)
                }
              }
            }
          }
        }
      }

      Section {
        id: todoSection
        x: leftCol.width + 14
        width: parent.width - leftCol.width - 14
        label: "todo ─ " + dropdownRoot.tdDayLabel
        labelColor: dropdownRoot.tdLegendColor
        borderColor: dropdownRoot.tdBorderColor
        // Stretches to match the left column's height, same as the
        // design mock's align-items:stretch -- otherwise the add-task
        // row below (bottomContent) would just sit directly under the
        // last todo row instead of staying pinned to the bottom.
        minHeight: leftCol.implicitHeight
        paddingTop: 14
        paddingBottom: 8
        paddingSide: 8
        spacing: 4

        rightContent: Text {
          text: dropdownRoot.tdSummary
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }

        Repeater {
          model: dropdownRoot.tdRows
          delegate: Item {
            id: todoRow
            required property var modelData
            width: parent.width
            height: Math.max(20, todoText.implicitHeight + 4)

            Rectangle {
              anchors.fill: parent
              radius: 2
              color: todoRow.modelData.isSel ? "#2f343e" : (todoMouse.containsMouse ? "#2f343e" : "transparent")
            }
            MouseArea {
              id: todoMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { dropdownRoot.calFocus = "todo"; dropdownRoot.tdSel = todoRow.modelData.idx; }
            }
            Text {
              x: 6
              y: 2
              width: 14
              text: todoRow.modelData.isSel ? "▌" : ""
              color: dropdownRoot.colors[0]
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              x: 20
              y: 2
              width: 28
              text: todoRow.modelData.box
              color: todoRow.modelData.boxColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
              MouseArea {
                anchors.fill: parent
                anchors.margins: -2
                cursorShape: Qt.PointingHandCursor
                onClicked: dropdownRoot.toggleTodoAt(todoRow.modelData.idx)
              }
            }
            Text {
              x: 48
              y: 2
              width: 42
              text: todoRow.modelData.time
              color: todoRow.modelData.timeColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              id: deleteText
              x: parent.width - 20
              y: 2
              width: 20
              text: "×"
              color: todoRow.modelData.isSel ? dropdownRoot.mutedColor : "transparent"
              font.family: "JetBrains Mono"
              font.pixelSize: 13
              MouseArea {
                anchors.fill: parent
                anchors.margins: -2
                cursorShape: Qt.PointingHandCursor
                onClicked: dropdownRoot.deleteTodoAt(todoRow.modelData.idx)
              }
            }
            Text {
              id: todoText
              x: 92
              y: 2
              width: Math.max(0, deleteText.x - 92 - 6)
              wrapMode: Text.WordWrap
              text: todoRow.modelData.text
              font.strikeout: todoRow.modelData.strike
              color: todoRow.modelData.textColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
        }

        Text {
          visible: dropdownRoot.tdRows.length === 0
          width: parent.width
          text: "nothing planned — press <font color='" + dropdownRoot.colors[2] + "'>a</font> to add"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }

        bottomContent: Rectangle {
          width: parent.width
          implicitHeight: 20
          color: tdInput.activeFocus ? "#2c313c" : "#1e2127"
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: tdInput.activeFocus ? dropdownRoot.colors[3] : dropdownRoot.hoverColor }
          Text {
            text: "+"
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            color: dropdownRoot.colors[3]
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          TextInput {
            id: tdInput
            anchors.left: parent.left
            anchors.right: submitLabel.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 6
            verticalAlignment: TextInput.AlignVCenter
            text: dropdownRoot.tdDraft
            color: dropdownRoot.fgColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
            selectByMouse: true
            onTextEdited: dropdownRoot.tdDraft = text
            onAccepted: dropdownRoot.addTodo()
          }
          Text {
            visible: tdInput.text.length === 0 && !tdInput.activeFocus
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: "new task · '14:00 text' sets a time"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.italic: true
            font.pixelSize: 12
          }
          Text {
            id: submitLabel
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: "[⏎]"
            color: dropdownRoot.colors[3]
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.addTodo() }
          }
        }
      }
    }

    Item { width: 1; height: 12 }

    // ----- hints -----
    Flow {
      width: parent.width
      spacing: 14
      Repeater {
        model: dropdownRoot.hints
        RowLayout {
          required property var modelData
          spacing: 4
          Text { text: modelData.k; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          Text { text: modelData.l; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        }
      }
    }
  }
}

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// ===== CALENDAR WIDGET =====
// Month grid (ISO week numbers, Monday-first by default) plus an agenda for
// the selected day. Events come from ~/.local/share/coel/events.json, an
// array of
//   { "date": "2026-10-06", "start": "10:00", "end": "10:15",
//     "title": "standup", "where": "#3b", "cal": "work" }
// with cal one of work | personal | health. The file is optional and watched;
// a real calendar sync (vdirsyncer/khal, ICS...) just needs to write it.
DesktopWidget {
  id: root

  property bool mondayFirst: true
  property bool showHints: true

  cardWidth: 360

  property var today: new Date()
  property var sel: new Date(today.getFullYear(), today.getMonth(), today.getDate())
  property var view: new Date(today.getFullYear(), today.getMonth(), 1)

  readonly property var calColors: ({ work: Pal.blue, personal: Pal.purple, health: Pal.green })

  // ----- events -----
  property var events: []
  readonly property var eventsByDay: {
    const m = {};
    for (const e of events) (m[e.date] = m[e.date] || []).push(e);
    return m;
  }
  FileView {
    path: (Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")) + "/events.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        const j = JSON.parse(text());
        root.events = Array.isArray(j) ? j : [];
      } catch (err) {
        console.warn("calendar: events.json is not valid JSON:", err);
        root.events = [];
      }
    }
    onLoadFailed: root.events = []
  }

  // Roll "today" over at midnight.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      const n = new Date();
      if (n.toDateString() !== root.today.toDateString()) root.today = n;
    }
  }

  function dkey(d) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }
  function isoWeek(d) {
    const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
    const dn = t.getUTCDay() || 7;
    t.setUTCDate(t.getUTCDate() + 4 - dn);
    const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
    return Math.ceil(((t - y0) / 864e5 + 1) / 7);
  }
  function shiftDay(n) {
    const d = new Date(sel.getFullYear(), sel.getMonth(), sel.getDate() + n);
    sel = d;
    view = new Date(d.getFullYear(), d.getMonth(), 1);
  }
  function shiftMonth(n) { view = new Date(view.getFullYear(), view.getMonth() + n, 1); }
  function goToday() {
    const n = new Date();
    today = n;
    sel = new Date(n.getFullYear(), n.getMonth(), n.getDate());
    view = new Date(n.getFullYear(), n.getMonth(), 1);
  }

  readonly property string todayKey: dkey(today)
  readonly property string selKey: dkey(sel)
  readonly property var rows: {
    const off = (view.getDay() - (mondayFirst ? 1 : 0) + 7) % 7;
    const daysIn = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();
    const nRows = Math.ceil((off + daysIn) / 7);
    const out = [];
    for (let r = 0; r < nRows; r++) {
      const cells = [];
      for (let c = 0; c < 7; c++) {
        const d = new Date(view.getFullYear(), view.getMonth(), r * 7 + c - off + 1);
        const evs = eventsByDay[dkey(d)] || [];
        const dots = [];
        for (const e of evs) { const col = calColors[e.cal] || Pal.blue; if (dots.indexOf(col) < 0) dots.push(col); }
        cells.push({
          date: d, key: dkey(d), day: d.getDate(),
          inMonth: d.getMonth() === view.getMonth(),
          weekend: d.getDay() === 0 || d.getDay() === 6,
          dots: dots.slice(0, 3)
        });
      }
      out.push({ cells: cells });
    }
    return out;
  }
  readonly property var dows: mondayFirst
    ? ["mo", "tu", "we", "th", "fr", "sa", "su"] : ["su", "mo", "tu", "we", "th", "fr", "sa"]
  readonly property var selEvents: (eventsByDay[selKey] || []).slice().sort(function (a, b) { return (a.start || "").localeCompare(b.start || ""); })
  readonly property string selLabel: {
    const rel = Math.round((new Date(sel.getFullYear(), sel.getMonth(), sel.getDate()) - new Date(today.getFullYear(), today.getMonth(), today.getDate())) / 864e5);
    if (rel === 0) return "today";
    if (rel === 1) return "tomorrow";
    if (rel === -1) return "yesterday";
    return Qt.formatDate(sel, "ddd MMM d").toLowerCase();
  }

  onKeyPressed: (e) => {
    let used = true;
    if (e.key === Qt.Key_H || e.key === Qt.Key_Left) shiftDay(-1);
    else if (e.key === Qt.Key_L || e.key === Qt.Key_Right) shiftDay(1);
    else if (e.key === Qt.Key_J || e.key === Qt.Key_Down) shiftDay(7);
    else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) shiftDay(-7);
    else if (e.key === Qt.Key_BracketLeft) shiftMonth(-1);
    else if (e.key === Qt.Key_BracketRight) shiftMonth(1);
    else if (e.key === Qt.Key_T) goToday();
    else used = false;
    e.accepted = used;
  }

  // ----- header -----
  RowLayout {
    Layout.fillWidth: true
    Layout.bottomMargin: 8
    spacing: 8
    Mono { text: "calendar"; font.weight: Font.Medium; color: root.focused ? Pal.blue : Pal.dim }
    Mono { Layout.fillWidth: true; text: "─ week " + root.isoWeek(root.today) + " ─"; color: Pal.muted }
    TextButton {
      hPad: 8
      onClicked: root.goToday()
      Mono { text: "t"; color: Pal.yellow }
      Mono { text: "today"; color: Pal.muted }
    }
  }

  // ----- month grid -----
  Box {
    id: monthBox
    Layout.fillWidth: true
    padTop: 14; padSide: 8; padBottom: 8
    borderColor: root.focused ? Pal.blue : Pal.faint

    leftData: [
      Item {
        width: prevText.implicitWidth + 4; height: prevText.implicitHeight
        Mono { id: prevText; anchors.centerIn: parent; text: "‹"; color: prevArea.containsMouse ? Pal.fg : Pal.muted }
        MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.shiftMonth(-1) }
      },
      Mono {
        text: Qt.formatDate(root.view, "MMMM yyyy").toLowerCase()
        color: root.focused ? Pal.blue : Pal.muted
      },
      Item {
        width: nextText.implicitWidth + 4; height: nextText.implicitHeight
        Mono { id: nextText; anchors.centerIn: parent; text: "›"; color: nextArea.containsMouse ? Pal.fg : Pal.muted }
        MouseArea { id: nextArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.shiftMonth(1) }
      }
    ]

    GridLayout {
      id: grid
      Layout.fillWidth: true
      columns: 7
      columnSpacing: 2
      rowSpacing: 2
      // from the box width, not our own: a GridLayout sizing its cells from
      // its own width collapses to zero
      readonly property real cellW: (monthBox.width - 16 - 6 * 2) / 7

      Repeater {
        model: root.dows
        delegate: Mono {
          required property string modelData
          Layout.preferredWidth: grid.cellW
          horizontalAlignment: Text.AlignHCenter
          text: modelData; font.pixelSize: 11
          color: (modelData === "sa" || modelData === "su") ? Pal.muted : Pal.dim
        }
      }

      Repeater {
        model: root.rows.length * 7
        delegate: Item {
          id: slot
          required property int index
          readonly property int r: Math.floor(index / 7)
          readonly property int c: index % 7
          readonly property var cell: root.rows[r].cells[c]
          readonly property bool isSel: cell.key === root.selKey
          readonly property bool isToday: cell.key === root.todayKey
          Layout.preferredWidth: grid.cellW
          Layout.preferredHeight: 30

          Rectangle {
            anchors.fill: parent
            radius: 2
            color: slot.isSel ? Pal.edge : "transparent"
            border.width: 1
            border.color: slot.isSel ? (root.focused ? Pal.blue : Pal.muted)
              : (dayArea.containsMouse ? Pal.muted : "transparent")
            Column {
              anchors.centerIn: parent
              spacing: 2
              Mono {
                anchors.horizontalCenter: parent.horizontalCenter
                text: slot.cell ? slot.cell.day : ""
                font.weight: slot.isToday ? Font.Medium : Font.Normal
                color: !slot.cell ? Pal.fg
                  : !slot.cell.inMonth ? Pal.faint
                  : slot.isToday ? Pal.yellow
                  : slot.cell.weekend ? Pal.dim : Pal.fg
              }
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 4
                spacing: 2
                Repeater {
                  model: slot.cell ? slot.cell.dots : []
                  delegate: Rectangle { required property color modelData; width: 4; height: 4; radius: 2; color: modelData }
                }
              }
            }
            MouseArea {
              id: dayArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.sel = slot.cell.date;
                root.view = new Date(slot.cell.date.getFullYear(), slot.cell.date.getMonth(), 1);
              }
            }
          }
        }
      }
    }
  }

  // ----- agenda -----
  Box {
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 4; padBottom: 8
    legend: "agenda ─ " + root.selLabel
    rightLegend: root.selEvents.length === 0 ? "" : root.selEvents.length + " event" + (root.selEvents.length > 1 ? "s" : "")

    Repeater {
      model: root.selEvents
      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
        Layout.leftMargin: 8; Layout.rightMargin: 8
        spacing: 6
        Mono { Layout.preferredWidth: 10; Layout.alignment: Qt.AlignTop; text: "│"; color: root.calColors[modelData.cal] || Pal.blue }
        Mono {
          Layout.preferredWidth: 92; Layout.alignment: Qt.AlignTop
          text: modelData.start + (modelData.end ? "–" + modelData.end : "")
          color: Pal.dim
        }
        Text {
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          font.family: Pal.mono; font.pixelSize: 12
          textFormat: Text.StyledText
          color: Pal.fg
          text: modelData.title.replace(/&/g, "&amp;").replace(/</g, "&lt;")
            + (modelData.where ? " <font color=\"" + Pal.muted + "\">· " + modelData.where.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>" : "")
        }
      }
    }
    Mono {
      visible: root.selEvents.length === 0
      Layout.leftMargin: 8
      text: "nothing scheduled"; color: Pal.muted
    }

    DashedLine {
      Layout.fillWidth: true
      Layout.topMargin: 8
      Layout.leftMargin: 8; Layout.rightMargin: 8
    }
    Row {
      Layout.leftMargin: 8
      Layout.topMargin: 6
      spacing: 12
      Repeater {
        model: [["work", Pal.blue], ["personal", Pal.purple], ["health", Pal.green]]
        delegate: Row {
          required property var modelData
          spacing: 7
          Mono { text: "●"; color: modelData[1] }
          Mono { text: modelData[0]; color: Pal.muted }
        }
      }
    }
  }

  Hints {
    visible: root.showHints
    Layout.fillWidth: true
    Layout.topMargin: 12
    items: [["hjkl", "day"], ["[ ]", "month"], ["t", "today"]]
  }
}

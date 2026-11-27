import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import ".."
import "../data"

// Calendar: C compact (the selected day's week + its events), M minimized.
// The selected day is shared with next up (CalendarData.selOffset). Keys: h/l
// day, [ ] week, t today; click a day to pick it. The month grid lives in the
// panel's calendar dropdown.
CardFrame {
  id: card
  property string size: "C"
  property string flavor: ""
  readonly property var cd: CalendarData

  title: "calendar"
  sub: "week " + cd.week
  summary: cd.summary
  minimized: size === "M"

  function handleKey(e) { return cd.handleDayKey(e); }

  rightData: [
    TextButton { onClicked: card.cd.shift(-1); Mono { text: "‹"; color: Pal.muted } },
    TextButton {
      visible: !card.cd.viewingToday
      onClicked: card.cd.goToday()
      Mono { text: "t"; color: Pal.yellow }
      Mono { text: "today"; color: Pal.muted }
    },
    TextButton { onClicked: card.cd.shift(1); Mono { text: "›"; color: Pal.muted } }
  ]

  RowLayout {
    Layout.fillWidth: true
    spacing: 2
    Repeater {
      model: card.cd.weekDays.length
      Rectangle {
        id: cell
        required property int index
        readonly property var d: card.cd.weekDays[index] || ({ colors: [] })
        Layout.fillWidth: true
        Layout.preferredHeight: dayCol.implicitHeight + 6
        radius: Globals.eyeCandyOff ? 0 : 2
        color: d.isSel ? Pal.faint : dayArea.containsMouse ? Pal.edge : "transparent"
        border.width: d.isToday && !d.isSel ? 1 : 0
        border.color: Pal.faint
        Column {
          id: dayCol
          anchors.centerIn: parent
          spacing: 1
          Mono { anchors.horizontalCenter: parent.horizontalCenter; text: cell.d.dow || ""; font.pixelSize: 11; color: cell.d.isSel ? Pal.fg : Pal.muted }
          Mono {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(cell.d.day || "")
            color: cell.d.isToday ? Pal.blue : cell.index > 4 ? Pal.muted : Pal.fg
            font.weight: cell.d.isToday || cell.d.isSel ? Font.Medium : Font.Normal
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 4
            spacing: 2
            Repeater {
              model: cell.d.colors
              Rectangle { required property var modelData; width: 4; height: 4; radius: 2; color: modelData }
            }
          }
        }
        MouseArea {
          id: dayArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: card.cd.select(cell.d.key)
        }
      }
    }
  }

  Box {
    Layout.fillWidth: true
    Layout.topMargin: 14
    padTop: 14; padSide: 12; padBottom: 10
    legend: card.cd.selLabel
    legendColor: card.cd.viewingToday ? Pal.muted : Pal.yellow
    Mono { visible: card.cd.selEvents.length === 0; text: "nothing on the calendar"; color: Pal.muted }
    Repeater {
      model: card.cd.selEvents.length
      RowLayout {
        required property int index
        readonly property var e: card.cd.selEvents[index] || ({})
        Layout.fillWidth: true
        spacing: 8
        Mono { Layout.preferredWidth: 48; text: parent.e.start || "all day"; color: Pal.muted }
        Rectangle { Layout.preferredWidth: 3; Layout.preferredHeight: 14; radius: 1; color: card.cd.colorOf(parent.e) }
        Mono { Layout.fillWidth: true; text: parent.e.title || ""; elide: Text.ElideRight }
      }
    }
  }
}

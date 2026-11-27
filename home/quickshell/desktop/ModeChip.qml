import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import ".."
import "../widgets"
import "../modes"

// The mode indicator, top-left of the desktop (Desktop Board `modeChip`):
// icon + mode, why, and "auto" or how long your pick holds; M opens the menu.
Item {
  id: chip
  property bool open: false
  signal clicked()

  readonly property var inf: Modes.info[Modes.mode]
  implicitWidth: row.implicitWidth + 24   // 12 px each side
  implicitHeight: 26

  RectangularShadow {
    anchors.fill: bg
    radius: bg.radius
    offset.y: 18
    blur: 32
    spread: -12
    color: Qt.rgba(0, 0, 0, 0.5)
  }
  Rectangle {
    id: bg
    anchors.fill: parent
    radius: Globals.eyeCandyOff ? 0 : 16
    color: Pal.card
    border.width: 1
    border.color: chip.open ? Pal.blue : Pal.faint
  }
  RowLayout {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    x: 12
    spacing: 8
    PhIcon { name: chip.inf.icon; color: chip.inf.color; font.pixelSize: 14 }
    Mono { text: Modes.label; color: chip.inf.color; font.weight: Font.Medium }
    Mono { visible: Modes.why !== ""; text: "─"; color: Pal.muted }
    Mono { visible: Modes.why !== ""; text: Modes.why; Layout.maximumWidth: 420; elide: Text.ElideRight }
    Mono { text: "─"; color: Pal.muted }
    PhIcon { visible: Modes.manual; name: "push-pin"; fill: true; color: Pal.yellow; font.pixelSize: 12 }
    Mono { visible: Modes.manual; text: "pinned"; color: Pal.yellow }
    Mono { text: Modes.manual ? Modes.holdText : "auto"; color: Pal.muted }
    Item { implicitWidth: 2 }
    Mono { text: "M"; color: Pal.yellow }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}

import QtQuick
import ".."
import "../widgets"

// Bordered chip: the slot options on each monitor row and the presets.
// 1px border (accent when selected), edge fill when selected or hovered.
Rectangle {
  id: chip

  property string label: ""
  property bool selected: false
  property bool dimmed: false
  property color accent: Pal.blue
  property int hPad: 8

  signal clicked()

  implicitWidth: text.implicitWidth + hPad * 2
  implicitHeight: text.implicitHeight
  radius: Globals.eyeCandyOff ? 0 : 2
  border.width: 1
  border.color: selected ? accent : Pal.faint
  color: selected || (area.containsMouse && !dimmed) ? Pal.edge : "transparent"
  opacity: dimmed ? 0.35 : 1

  Mono {
    id: text
    anchors.centerIn: parent
    text: chip.label
    color: chip.selected ? Pal.fg : Pal.dim
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: chip.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}

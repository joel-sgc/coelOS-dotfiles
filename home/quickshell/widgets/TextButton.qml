import QtQuick

// Flat text button: transparent, lights up #404754 on hover. Children (Mono
// pieces, usually a yellow key letter then a label) sit in a Row.
Rectangle {
  id: btn

  signal clicked()
  property int hPad: 6
  property color hoverColor: Pal.faint
  default property alias content: row.data
  readonly property bool hovered: area.containsMouse

  implicitWidth: row.implicitWidth + hPad * 2
  implicitHeight: row.implicitHeight
  radius: 2
  color: hovered ? hoverColor : "transparent"

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 7
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: btn.clicked()
  }
}

import QtQuick
import ".."
import QtQuick.Layouts
import "../widgets"

// One selectable source (screen or window): thumbnail slot, radio mark + name,
// and a detail line. Selection/focus drawn like the mockup's cards.
Rectangle {
  id: card

  property bool selected: false
  property bool focusedCard: false
  property string name: ""
  property string detail: ""
  property int detailLines: 2
  property string tag: ""             // right-aligned small label (e.g. "primary")
  default property alias thumb: thumbSlot.data
  property real thumbAspect: 16 / 10

  signal picked()
  signal activated()

  implicitHeight: col.implicitHeight + 16
  radius: Globals.eyeCandyOff ? 0 : 8
  color: selected ? Pal.edge : "transparent"
  border.width: 1
  border.color: selected ? Pal.blue : focusedCard ? Pal.muted : (area.containsMouse ? Pal.muted : "#3e4451")

  ColumnLayout {
    id: col
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
    spacing: 6

    Item {
      id: thumbSlot
      Layout.fillWidth: true
      Layout.preferredHeight: width / card.thumbAspect
    }
    RowLayout {
      Layout.fillWidth: true
      spacing: 6
      Mono { text: card.selected ? "(•)" : "( )"; color: card.selected ? Pal.blue : Pal.muted }
      Mono {
        Layout.fillWidth: true
        text: card.name
        color: card.selected ? Pal.fg : Pal.dim
        elide: Text.ElideRight
      }
      Mono { visible: card.tag !== ""; text: card.tag; font.pixelSize: 11; color: Pal.muted }
    }
    Mono {
      Layout.fillWidth: true
      text: card.detail
      font.pixelSize: 11
      color: Pal.muted
      wrapMode: Text.Wrap
      maximumLineCount: card.detailLines
      elide: Text.ElideRight
      lineHeight: 1.1
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: card.picked()
    onDoubleClicked: card.activated()
  }
}

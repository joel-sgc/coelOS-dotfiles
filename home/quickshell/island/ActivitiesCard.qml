import QtQuick
import ".."
import "Parts.js" as P

// "Now · n activities": what hovering the dock opens when 2+ chips are up.
// Each row opens that activity's own card (or runs its action).
Column {
  id: card
  property var engine
  property var screen

  width: 360
  spacing: 2

  CardHead {
    width: parent.width
    icon: "pulse"
    title: "Now"
    sub: "· " + (card.engine ? card.engine.chips.length : 0) + " activities"
  }
  Item { width: 1; height: 6 }

  Repeater {
    // By count, not the array: see IslandRow.qml.
    model: card.engine ? card.engine.chips.length : 0
    Rectangle {
      id: rowItem
      required property int index
      readonly property var modelData: card.engine.chips[index] || ({ parts: [] })
      width: card.width
      height: 28
      radius: Globals.eyeCandyOff ? 0 : 5
      color: area.containsMouse ? P.C.sf : "transparent"

      IslandRow {
        id: chipRow
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        groups: rowItem.modelData.parts
      }
      Text {
        anchors.left: chipRow.right
        anchors.leftMargin: 10
        anchors.right: value.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: rowItem.modelData.label || ""
        textFormat: Text.PlainText
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        color: P.C.fg
      }
      Text {
        id: value
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: rowItem.modelData.value || ""
        textFormat: Text.PlainText
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        color: rowItem.modelData.valueColor || P.C.fg
      }
      MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          const c = rowItem.modelData;
          if (c.card) card.engine.openCard(c.id, true, card.screen);
          else if (c.activate) { card.engine.closeCard(); c.activate(); }
        }
      }
    }
  }

  Text {
    topPadding: 6
    text: "click a row for its card"
    font.family: "JetBrains Mono"
    font.pixelSize: 12
    color: P.C.mu
  }
}

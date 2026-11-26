import QtQuick
import "../sysPanel/Phosphor.js" as Phosphor
import "Parts.js" as P

// The board's `head`: icon, title, muted subtitle, muted text on the right.
Item {
  id: head
  property string icon: ""
  property color tint: P.C.fg
  property string title: ""
  property string sub: ""
  property string trailing: ""

  implicitHeight: 20
  implicitWidth: left.implicitWidth + (trailing !== "" ? rightText.implicitWidth + 12 : 0)

  Row {
    id: left
    spacing: 8
    anchors.verticalCenter: parent.verticalCenter
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: Phosphor.icon(head.icon)
      font.family: "Phosphor"
      font.pixelSize: 15
      color: head.tint
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: head.title
      textFormat: Text.PlainText
      font.family: "JetBrains Mono"
      font.pixelSize: 12
      font.weight: Font.Medium
      color: P.C.fg
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: head.sub
      textFormat: Text.PlainText
      font.family: "JetBrains Mono"
      font.pixelSize: 12
      color: P.C.mu
    }
  }
  Text {
    id: rightText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, Math.max(0, head.width - left.implicitWidth - 12))
    elide: Text.ElideMiddle
    text: head.trailing
    textFormat: Text.PlainText
    font.family: "JetBrains Mono"
    font.pixelSize: 12
    color: P.C.mu
  }
}

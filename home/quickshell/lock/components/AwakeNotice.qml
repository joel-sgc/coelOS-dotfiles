import QtQuick
import "../../sysPanel/Phosphor.js" as Phosphor

// A one-line notice that the machine is being kept awake, and by whom -- shown
// on the login screen, because that is where the idle dimming and the suspend
// would otherwise have happened (modules/session-hub.nix). Hidden when empty.
Row {
  id: root

  property string text: ""
  property color color: "#e5c07b"

  visible: text !== ""
  spacing: 8

  Text {
    text: Phosphor.icon("sun-dim")
    color: root.color
    font.family: "Phosphor"
    font.pixelSize: 14
    anchors.verticalCenter: parent.verticalCenter
  }
  Text {
    text: root.text
    color: root.color
    font.family: "JetBrains Mono"
    font.pixelSize: 12
    anchors.verticalCenter: parent.verticalCenter
  }
}

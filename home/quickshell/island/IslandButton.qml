import QtQuick
import ".."
import "../sysPanel/Phosphor.js" as Phosphor
import "Parts.js" as P

// The board's `btn`: 22 px, outlined (or filled when `primary`), optional icon.
Rectangle {
  id: btn
  property string text: ""
  property string icon: ""
  property bool iconFill: false
  property color tint: P.C.fg
  property bool primary: false
  signal clicked()

  // Disabled (e.g. printer unreachable): dimmed, no hover, no clicks.
  opacity: enabled ? 1 : 0.4
  implicitWidth: row.implicitWidth + 18
  implicitHeight: 22
  radius: Globals.eyeCandyOff ? 0 : 5
  color: primary ? tint : (area.containsMouse ? P.C.sf : "transparent")
  border.width: primary ? 0 : 1
  border.color: P.C.sf

  readonly property string fillFamily: Qt.fontFamilies().indexOf("Phosphor-Fill") >= 0 ? "Phosphor-Fill" : "Phosphor"

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6
    Text {
      visible: btn.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: btn.icon !== "" ? Phosphor.icon(btn.icon) : ""
      font.family: btn.iconFill ? btn.fillFamily : "Phosphor"
      font.pixelSize: 11
      color: btn.primary ? P.C.bg : btn.tint
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: btn.text
      textFormat: Text.PlainText
      font.family: "JetBrains Mono"
      font.pixelSize: 11
      font.weight: btn.primary ? Font.Medium : Font.Normal
      color: btn.primary ? P.C.bg : btn.tint
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: btn.enabled
    cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: btn.clicked()
  }
}

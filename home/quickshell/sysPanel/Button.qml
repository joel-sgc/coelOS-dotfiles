import QtQuick
import QtQuick.Layouts
import Quickshell

// ===== BUTTON =====
// Generic pill button matching the design mock's bar chips exactly: fixed
// 26px height, 5px-radius hover background, 7px horizontal padding,
// Phosphor icon (14px) + optional JetBrains Mono label (13px), 6px gap
// between them. The mock draws every bar button (workspace, tray, bt/net/
// audio/sys/pwr) at this same height/radius/hover treatment; only the
// content and per-button icon size (Battery.qml bumps to 15) differ.
Item {
  id: buttonRoot

  property var command: []
  // Only cpu (left: btop, right: plain terminal) uses this, matching
  // waybar's on-click/on-click-right split -- empty means right-click is a
  // no-op, same as every other button that never set it.
  property var rightCommand: []

  property string icon: ""
  property string label: ""
  property int iconSize: 14
  property int labelSize: 13
  // 0 means unconstrained. labelMinWidth right-aligns and reserves space
  // (Cpu.qml's "NN%" not jittering the row's width as the digit count
  // changes); labelMaxWidth elides (Network.qml's essid, which can be
  // arbitrarily long) -- both match specific mock behaviors, not just a
  // generic just-in-case knob.
  property int labelMinWidth: 0
  property int labelMaxWidth: 0

  implicitWidth: row.implicitWidth + 14
  implicitHeight: 26

  Rectangle {
    anchors.fill: parent
    radius: 5
    color: mouseArea.containsMouse ? root.hoverColor : "transparent"
  }

  RowLayout {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    x: 7
    spacing: 6

    Text {
      text: buttonRoot.icon
      color: root.fgColor
      font.family: "Phosphor"
      font.pixelSize: buttonRoot.iconSize
    }

    Text {
      visible: buttonRoot.label.length > 0
      text: buttonRoot.label
      color: root.fgColor
      font.family: "JetBrains Mono"
      font.pixelSize: buttonRoot.labelSize
      horizontalAlignment: Text.AlignRight
      elide: buttonRoot.labelMaxWidth > 0 ? Text.ElideRight : Text.ElideNone
      Layout.minimumWidth: buttonRoot.labelMinWidth
      Layout.maximumWidth: buttonRoot.labelMaxWidth > 0 ? buttonRoot.labelMaxWidth : Infinity
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: (mouse) => {
      if (mouse.button === Qt.RightButton && buttonRoot.rightCommand.length > 0) {
        Quickshell.execDetached(buttonRoot.rightCommand);
      } else {
        Quickshell.execDetached(buttonRoot.command);
      }
    }
  }
}

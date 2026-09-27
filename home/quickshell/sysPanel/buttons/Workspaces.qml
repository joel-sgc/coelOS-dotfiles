import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// ===== WORKSPACES  =====
// Chip sizing/spacing/hover matches the mock exactly: 2px gap between
// chips, min-width 22/height 26 each, 5px-radius hover background (same
// treatment every other bar button gets), 14px numbers, and a per-chip
// weight (bold only while focused, not every number all the time).
RowLayout {
  spacing: 2

  Repeater {
    model: root.workspaceCount

    delegate: Rectangle {
      id: wsDelegate
      required property int index
      property int wsNum: index + 1
      property var wsData: {
        for (const ws of Hyprland.workspaces.values) {
          if (ws.id === wsNum) return ws
        }
        return null
      }
      property bool focused: wsData !== null && wsData.focused

      Layout.alignment: Qt.AlignVCenter
      implicitWidth: Math.max(22, wsText.implicitWidth + 8)
      height: 26
      radius: 5
      color: wsMouseArea.containsMouse ? root.hoverColor : "transparent"

      MouseArea {
        id: wsMouseArea
        anchors.fill: parent
        onClicked: Hyprland.dispatch("workspace " + wsDelegate.wsNum)
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
      }

      Text {
        id: wsText
        anchors.centerIn: parent
        text: wsDelegate.wsNum
        color: root.colors[wsDelegate.index % root.colors.length]
        font.family: "JetBrains Mono"
        font.pixelSize: 14
        font.weight: wsDelegate.focused ? Font.DemiBold : Font.Normal
        opacity: {
          if (!wsDelegate.wsData) return wsMouseArea.containsMouse ? .5 : .2
          if (wsDelegate.wsData.focused) return 1
          if (wsDelegate.wsData.toplevels.values.length > 0) return .5
          if (wsMouseArea.containsMouse) return .5
          return .2
        }
      }

      // Focused-workspace mark -- a short underline rather than another
      // opacity cue, so "which workspace is focused" reads at a glance
      // without having to compare every number's opacity against the rest.
      Rectangle {
        anchors {
          left: parent.left
          right: parent.right
          bottom: parent.bottom
          leftMargin: 6
          rightMargin: 6
          bottomMargin: 1
        }
        height: 2
        radius: 1
        color: root.colors[wsDelegate.index % root.colors.length]
        opacity: {
          if (wsDelegate.wsData && wsDelegate.wsData.focused) return 1
          if (wsMouseArea.containsMouse) return .5
          return 0
        }
      }
    }
  }
}
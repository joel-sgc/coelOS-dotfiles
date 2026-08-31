import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// ===== WORKSPACES  =====
RowLayout {
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
    
      Layout.alignment: Qt.AlignVCenter
      width: 24
      height: 24
      color: "transparent"
    
      MouseArea {
        id: wsMouseArea
        property bool hovering: false
        anchors.fill: parent
        onClicked: Hyprland.dispatch("workspace " + wsDelegate.wsNum)
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        
        onEntered: hovering = true
        onExited: hovering = false
      }
    
      Text {
        anchors.centerIn: parent
        text: wsDelegate.wsNum
        color: root.colors[wsDelegate.index % root.colors.length]
        font.bold: true
        opacity: {
          if (!wsDelegate.wsData) return wsMouseArea.containsMouse ? .5 : .2
          if (wsDelegate.wsData.focused) return 1
          if (wsDelegate.wsData.toplevels.values.length > 0) return .5
          if (wsMouseArea.containsMouse) return .5
          return .2
        }
      }
    }    
  }
}
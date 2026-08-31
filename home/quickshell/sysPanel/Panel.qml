import Quickshell
import Quickshell.Hyprland
import QtQuick.Layouts

PanelWindow {
  id: root  
  property var bgColor: "#282c34"
  property var fgColor: "#abb2bf"
  property var colors: [
    "#61afef",  // Blue
    "#ef596f",  // Red
    "#e5c07b",  // Yellow
    "#89ca78",  // Green
    "#d55fde"   // Purple
  ]
  
  property int workspaceCount: {
    let maxWs = 5;
    for (const ws of Hyprland.workspaces.values) {
      if (ws.id > maxWs) maxWs = ws.id;
    }
    return maxWs;
  }

  anchors {
    top: true
    left: true
    right: true
  }
  
  implicitHeight: 48
  color: root.bgColor
  
  RowLayout {
    anchors.verticalCenter: parent.verticalCenter
    spacing: 16
    
    Logo {
      Layout.leftMargin: 16
    }
        
    Workspaces {  }
  }
}
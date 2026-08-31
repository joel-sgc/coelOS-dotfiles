import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

import "./sysPanel"

ShellRoot {
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
  
  // Waybar-like panel  
  Panel {
    colors: root.colors
    bgColor: root.bgColor
    fgColor: root.fgColor
  }
  
  // Wraparound border  
  Border {
    borderColor: root.bgColor
  }
}
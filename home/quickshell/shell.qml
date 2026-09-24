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
  // Dimmed/secondary text -- tray icons at rest, separators between button
  // groups. Same value the design mock uses for both roles.
  property var mutedColor: "#5c6370"
  // Hover background for every bar chip (workspace, logo, clock, tray,
  // bt/net/audio/sys/pwr) -- also doubles as the tray group's separator
  // line color in the mock, which is the same #404754.
  property var hoverColor: "#404754"
  property var colors: [
    "#61afef",  // Blue
    "#ef596f",  // Red
    "#e5c07b",  // Yellow
    "#89ca78",  // Green
    "#d55fde"   // Purple
  ]
  // Single source of truth for the bar's height -- Border needs it too
  // (its overlay leaves a barHeight-tall gap at the top), and Popup.qml's
  // instances anchor their top margin to it as well.
  property int barHeight: 36

  // Waybar-like panel
  Panel {
    colors: root.colors
    bgColor: root.bgColor
    fgColor: root.fgColor
    mutedColor: root.mutedColor
    hoverColor: root.hoverColor
    barHeight: root.barHeight
  }

  // Wraparound border
  Border {
    borderColor: root.bgColor
    barHeight: root.barHeight
  }
}
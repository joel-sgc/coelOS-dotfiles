import Quickshell
import Quickshell.Wayland
import QtQuick

// Maps a 1x1 invisible layer surface on every screen for a moment. Hyprland
// re-arranges an output's layer surfaces (bar, border, wallpaper) whenever
// one is mapped on it, and after a monitor mode change it can leave them at
// stale sizes until something does -- opening the launcher on that screen
// used to be the only thing that fixed it. Call fire() once the outputs have
// settled.
Scope {
  id: root

  property bool active: false

  function fire() {
    active = true;
    off.restart();
  }

  Timer {
    id: off
    interval: 200
    onTriggered: root.active = false
  }

  Variants {
    model: Quickshell.screens
    delegate: PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.active
      color: "transparent"
      implicitWidth: 1
      implicitHeight: 1
      anchors { top: true; left: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "coel-displays-nudge"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }
  }
}

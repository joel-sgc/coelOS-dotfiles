import Quickshell
import QtQuick

import "./displays"

// ===== DISPLAY MODES ENTRY POINT =====
// Standalone, short-lived Quickshell process (same convention as
// power-menu-shell.qml / screenshare-shell.qml), started by coel-displays
// (home/os-commands.nix). LayerNudge re-arranges every screen's layer
// surfaces once a layout change has settled -- see its own comment.
ShellRoot {
  DisplayModes { id: modes }
  LayerNudge { id: nudge }
  Connections {
    target: modes.backend
    function onSettled() { nudge.fire(); }
  }
}

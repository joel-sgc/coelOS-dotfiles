import QtQuick
import Quickshell
import Quickshell.Wayland

import "./powermenu"

// ===== POWER MENU ENTRY POINT =====
// Launched fresh by coel-power-menu (home/os-commands.nix) on every
// XF86PowerOff press (home/hyprland.nix) -- a separate, standalone
// Quickshell process that exits when the menu closes, same one-shot
// convention as coel-screenshot/coel-screenrecord, not a long-running
// shell like Panel.qml's. Points at the live repo path the same way
// lock-real-shell.qml/hypridle.nix's lockCmd do, so edits here hot-reload
// without a rebuild.
//
// Full-screen + Overlay + Exclusive keyboard focus (not Popup.qml's
// OnDemand): this has no parent bar window to share a HyprlandFocusGrab
// with, and needs to reliably own every keypress (arrows, digits, letter
// hotkeys, Escape) for as long as it's open, the same requirement the
// lock screen's own real surface has.
ShellRoot {
  PanelWindow {
    id: win
    visible: true
    color: "transparent"

    anchors {
      top: true
      left: true
      right: true
      bottom: true
    }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "coel-power-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    PowerMenu {
      anchors.fill: parent
      onCloseRequested: Qt.quit()
    }
  }
}

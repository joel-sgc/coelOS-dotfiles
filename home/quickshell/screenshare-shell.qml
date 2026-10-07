import Quickshell
import "./screenshare"

// ===== SCREEN SHARE PICKER (entry) =====
// Standalone, short-lived Quickshell process started by xdg-desktop-portal-
// hyprland through `coel-share-picker` (home/os-commands.nix), same
// independent-process convention as power-menu-shell.qml / lock-real-shell.qml.
// Shows one dialog, writes the portal's selection line to $COEL_PICKER_OUT,
// and exits. Contract details: screenshare/SharePicker.qml.
ShellRoot {
  SharePicker {}
}

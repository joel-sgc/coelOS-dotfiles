pragma Singleton
import Quickshell
import QtQuick

// Single global switch for whether Quickshell's own rendered chrome
// (panel/popups/widgets/dialogs -- everything NOT drawn by Hyprland
// itself) shows rounded corners. TogglesBackend.qml's eye-candy toggle
// sets this alongside the real hyprctl decoration:rounding keyword it
// already flips: that keyword only affects window decoration Hyprland
// itself draws, and has no say over anything Quickshell paints inside
// its own layer-shell surfaces.
//
// A real singleton (same pattern as widgets/Pal.qml, not this repo's
// usual threaded-prop convention for bgColor/fgColor/etc) since this
// needs to reach ~150 radius bindings spread across nearly every file in
// the quickshell tree, most of which have no other reason to receive new
// props from their parents -- threading one more prop through every
// intermediate layer down to each of them would touch just as many
// files for no benefit over a single shared value they can all read
// directly.
Singleton {
  property bool eyeCandyOff: false
}

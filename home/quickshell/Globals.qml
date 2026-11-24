pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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

  // Hyprland's own window corner radius (decoration:rounding, i.e. settings.toml
  // [config.decoration]), re-read on every config reload. Desktop widget cards
  // use it so they round like windows do. eyeCandyOff still wins where checked.
  property int windowRounding: 8
  Process {
    id: roundingProc
    command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const v = Number(JSON.parse(text).int);
          if (!isNaN(v) && v >= 0) windowRounding = v;
        } catch (e) {
          console.warn("globals: could not read decoration:rounding:", e);
        }
      }
    }
  }
  Component.onCompleted: roundingProc.running = true
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") roundingProc.running = true;
    }
  }
}

pragma Singleton
import Quickshell
import QtQuick

// Colors/fonts shared by every desktop widget. Values mirror shell.qml's
// palette and home/theme/onedark.nix (the One-Dark variant used everywhere),
// plus the few extra tones the widgets mockup uses (cyan, orange, tracks).
Singleton {
  readonly property color card: "#282c34"     // widget + modal background
  readonly property color deep: "#1e2127"     // text inputs
  readonly property color raised: "#2c313c"   // focused input / drop target
  readonly property color edge: "#2f343e"     // unfocused card border, hover/selected row
  readonly property color faint: "#404754"    // box borders, week numbers, button hover
  readonly property color track: "#353b45"    // bar tracks
  readonly property color muted: "#5c6370"
  readonly property color dim: "#7f848e"
  readonly property color fg: "#abb2bf"
  readonly property color blue: "#61afef"
  readonly property color red: "#ef596f"
  readonly property color yellow: "#e5c07b"
  readonly property color green: "#89ca78"
  readonly property color purple: "#d55fde"
  readonly property color cyan: "#2bbac5"
  readonly property color orange: "#d19a66"

  readonly property string mono: "JetBrains Mono"
  // Solid weather icons; falls back to the Regular weight until the
  // Phosphor-Fill font (home/quickshell-phosphor-font.nix) is installed.
  readonly property string fillFamily: Qt.fontFamilies().indexOf("Phosphor-Fill") >= 0 ? "Phosphor-Fill" : "Phosphor"
}

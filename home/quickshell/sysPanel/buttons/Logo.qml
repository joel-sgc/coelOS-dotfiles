import QtQuick
import QtQuick.Effects
import "../.."
import Quickshell
import Quickshell.Widgets

// ===== LOGO =====
// A proper chip like the bar's other buttons now (28x28, radius 6, hover
// background matching the mock) -- previously a bare icon + MouseArea
// with no chrome at all. Renamed the root id away from "root" (it used to
// shadow the outer PanelWindow's "root", which is how every sibling file
// reaches panel state -- harmless before since this file never needed
// root.*, but it does now for hoverColor).
//
// Used to run coel-main-menu (an external rofi script) directly via
// Quickshell.execDetached -- now emits clicked() instead, same as every
// other bar button, so Panel.qml can toggle the in-process Launcher
// (Launcher.qml/LauncherPanel.qml) that replaces it.
Item {
  id: logoRoot

  signal clicked()

  // The SVG is plain white; this recolors it. Any color works (it multiplies
  // nothing -- the effect replaces the RGB and keeps the icon's alpha, so the
  // shape stays crisp). Set it to "transparent" to show the SVG as-is.
  property color tint: "#61afef"

  implicitWidth: 28
  implicitHeight: 28

  Rectangle {
    anchors.fill: parent
    radius: Globals.eyeCandyOff ? 0 : 6
    // Always shown, as the hover color at half strength; hovering firms it up.
    color: Qt.alpha(root.hoverColor, mouseArea.containsMouse ? 1.0 : 0.5)
    Behavior on color { ColorAnimation { duration: Globals.eyeCandyOff ? 0 : 120 } }
  }

  IconImage {
    anchors.centerIn: parent
    source: Qt.resolvedUrl("../../assets/logo.svg")
    mipmap: true
    implicitSize: 16
    layer.enabled: logoRoot.tint.a > 0
    layer.effect: MultiEffect {
      colorization: 1.0
      colorizationColor: logoRoot.tint
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: logoRoot.clicked()
  }
}
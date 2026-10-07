import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../widgets"

// Result card shown after a request ends (authorized / failed / dismissed).
// Top-right, same spot and corner as the notification toasts, never takes focus.
PanelWindow {
  id: win

  property string kind: "ok"       // ok | fail | cancel
  property string title: ""
  property string sub: ""
  property bool shown: false

  readonly property color tone: kind === "ok" ? Pal.green : kind === "fail" ? Pal.red : Pal.dim
  readonly property string glyph: kind === "ok" ? "lock-simple-open" : kind === "fail" ? "warning" : "x-circle"

  visible: shown
  anchors { top: true; right: true }
  margins { top: 44; right: 20 }
  implicitWidth: 320
  implicitHeight: card.implicitHeight
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "coel-polkit-toast"

  Rectangle {
    id: card
    width: parent.width
    implicitHeight: row.implicitHeight + 20
    radius: 16
    color: Pal.card
    border.width: 1
    border.color: Pal.faint

    RowLayout {
      id: row
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 12 }
      spacing: 10
      PhIcon { name: win.glyph; font.pixelSize: 18; color: win.tone }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Mono { Layout.fillWidth: true; text: win.title; color: win.tone; elide: Text.ElideRight }
        Mono { Layout.fillWidth: true; text: "polkit · " + win.sub; color: Pal.muted; elide: Text.ElideRight }
      }
    }
  }
}

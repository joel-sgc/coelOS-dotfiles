import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// ===== DESKTOP WIDGET BASE =====
// A card pinned to the desktop: wlr-layer-shell Bottom layer, so it sits
// above the wallpaper but under every real window, and reserves no space
// (ExclusionMode.Ignore). Children declared inside a DesktopWidget land in a
// ColumnLayout inside the card; the window sizes itself to that content.
//
// Positioned by margins from the top-left (a layer-shell surface has no
// absolute position, only anchors + margins).
//
// Keyboard: OnDemand focus, so clicking a widget gives it the keys (hjkl and
// friends -- see each widget's onKeyPressed); `focused` drives the brighter
// border / blue title. Text entry (the kanban card editor) is a separate
// Overlay window, see KanbanEditor.qml.
PanelWindow {
  id: win

  property int marginTop: 60
  property int marginLeft: 40
  property bool shown: true
  property int cardWidth: 360
  readonly property bool focused: keys.Window.active
  default property alias content: body.data

  signal keyPressed(var event)

  visible: shown
  anchors { top: true; left: true }
  margins { top: win.marginTop; left: win.marginLeft }
  implicitWidth: win.cardWidth
  implicitHeight: body.implicitHeight + 20

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  WlrLayershell.namespace: "coel-widget"

  Rectangle {
    anchors.fill: parent
    radius: 16
    color: Pal.card
    border.width: 1
    border.color: win.focused ? Pal.faint : Pal.edge
  }

  FocusScope {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.onPressed: (e) => win.keyPressed(e)

    ColumnLayout {
      id: body
      anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 10 }
      spacing: 0
    }
  }
}

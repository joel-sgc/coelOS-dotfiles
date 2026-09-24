import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ===== POPUP =====
// Shared dropdown chrome for every future bar button's popup (bluetooth,
// network, audio, ..., and the calendar wired up here as the first user).
// This is plumbing only -- no per-widget content lives here.
//
// Why this is its own PanelWindow rather than an Item drawn over the bar:
// a layer-shell surface (which PanelWindow is) can't paint outside its own
// buffer, so a dropdown that needs to extend below the 36px bar has to be
// a window of its own, anchored just under it -- the same reason
// Border.qml is a separate window rather than an Item inside Panel.qml.
//
// Keyboard + mouse dismissal both go through HyprlandFocusGrab: it grabs
// input focus across `windows` while `active`, and fires `cleared` on a
// click outside every grabbed window OR on focus loss (which also covers
// Escape, since WlrKeyboardFocus.OnDemand below hands focus back to
// whatever was focused before on Escape, triggering the same signal) --
// one mechanism for "click outside" and "Escape" instead of two.
PanelWindow {
  id: popupRoot

  property bool open: false
  property int barHeight: 36
  // Anchored to the bar's right edge by default (most buttons live
  // there); set centerHorizontally for the ones under the bar's center
  // (currently just the clock/calendar).
  property bool centerHorizontally: false
  property int rightMargin: 0
  property int minimumWidth: 160

  // Named "content", not "data" -- PanelWindow already has its own "data"
  // (that's what plain PanelWindow { Item { ... } } usage relies on
  // elsewhere in this repo), and redeclaring a property under the same
  // name as one it inherits is a collision, not an override.
  default property alias content: contentContainer.data

  visible: open
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  anchors {
    top: true
    right: !centerHorizontally
  }
  margins {
    top: barHeight
    right: rightMargin
  }

  implicitWidth: frame.implicitWidth
  implicitHeight: frame.implicitHeight

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  HyprlandFocusGrab {
    windows: [ popupRoot ]
    active: popupRoot.open
    onCleared: popupRoot.open = false
  }

  Rectangle {
    id: frame

    implicitWidth: Math.max(popupRoot.minimumWidth, contentContainer.childrenRect.width + 24)
    implicitHeight: contentContainer.childrenRect.height + 24
    width: implicitWidth
    height: implicitHeight

    color: "#282c34"
    radius: 12
    border.width: 1
    border.color: "#404754"

    Item {
      id: contentContainer
      x: 12
      y: 12
      width: parent.width - 24
      height: parent.height - 24
    }
  }

  Item {
    focus: popupRoot.open
    anchors.fill: parent
    Keys.onEscapePressed: popupRoot.open = false
  }
}

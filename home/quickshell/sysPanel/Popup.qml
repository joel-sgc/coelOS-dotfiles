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
// Escape reaching this component's own Keys.onEscapePressed below, since
// WlrKeyboardFocus.OnDemand hands focus back to whatever was focused
// before on Escape, triggering the same signal) -- one mechanism for
// "click outside" and "Escape" instead of two.
//
// `open` is meant to be a caller-owned binding (Panel.qml's `root.openPopup
// === "power"`, say), not something this component's internals ever
// re-point at a literal value: assigning straight to `open` from inside
// (the previous version did, in the focus-grab and Escape handlers) would
// silently sever that binding the first time the popup closed itself --
// after which no click could ever reopen it, since `open` would be stuck
// on the value it was overwritten with. closeRequested() lets the owner's
// own binding stay intact and just update its source property instead.
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
  // 0 means auto-size to content's natural (childrenRect) size. Set this
  // for a dropdown whose layout targets one specific width regardless of
  // what's in it right now -- the design mock's power dropdown is a fixed
  // 470px, not something that reflows to fit its content.
  property int contentWidth: 0

  signal closeRequested()

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
    onCleared: popupRoot.closeRequested()
  }

  Rectangle {
    id: frame

    implicitWidth: popupRoot.contentWidth > 0
      ? popupRoot.contentWidth
      : Math.max(popupRoot.minimumWidth, contentContainer.childrenRect.width + 32)
    implicitHeight: contentContainer.childrenRect.height + 20
    width: implicitWidth
    height: implicitHeight

    color: "#282c34"
    radius: 12
    border.width: 1
    border.color: "#404754"

    // 16px sides / 6px top / 14px bottom -- every dropdown in the design
    // mock uses this exact padding, not just the power one built first.
    // A FocusScope, not a plain Item: it's what lets whatever content is
    // placed inside (PowerDropdown.qml, and later ones) request and hold
    // keyboard focus of its own for its own keymap (1/2/3, j/k, h/l, ...)
    // while this scope is active, with Escape still falling back to
    // closeRequested() below if the content doesn't handle it itself.
    FocusScope {
      id: contentContainer
      x: 16
      y: 6
      width: parent.width - 32
      height: parent.height - 20
      focus: popupRoot.open

      Keys.onEscapePressed: popupRoot.closeRequested()
    }
  }
}

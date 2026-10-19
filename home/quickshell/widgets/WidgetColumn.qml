import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// ===== WIDGET COLUMN =====
// The layer-shell window that hosts a stack of WidgetCards: wlr-layer-shell
// Bottom layer, so it sits above the wallpaper but under every real window,
// and reserves no space (ExclusionMode.Ignore). The cards are laid out by a
// ColumnLayout inside, so minimizing one moves the ones below it by layout
// alone.
//
// The window itself never resizes: it is anchored top *and* bottom, a full-
// height strip, and the layout sits at its top (or bottom, anchorBottom). A
// resizing surface needs a compositor round-trip per change, which showed as
// flashing and jumping on minimize; a fixed surface just repaints. The strip
// is transparent and the input mask covers only the cards, so clicks anywhere
// else go straight through to whatever is underneath.
PanelWindow {
  id: win

  property int marginTop: 60
  property int marginBottom: 40
  property int marginLeft: 40
  property int marginRight: 40
  property bool anchorRight: false
  property bool anchorBottom: false
  property bool shown: true
  property int gap: 20
  default property alias content: col.data

  visible: shown
  anchors { top: true; bottom: true; left: !win.anchorRight; right: win.anchorRight }
  margins { top: win.marginTop; bottom: win.marginBottom; left: win.marginLeft; right: win.marginRight }
  implicitWidth: col.implicitWidth
  // Explicit bounds rather than `item: col`: a bottom-anchored column moves
  // when the surface is configured, and this guarantees the click region
  // follows it.
  mask: Region { x: col.x; y: col.y; width: col.width; height: col.height }

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  WlrLayershell.namespace: "coel-widget"

  ColumnLayout {
    id: col
    anchors {
      left: parent.left; right: parent.right
      top: win.anchorBottom ? undefined : parent.top
      bottom: win.anchorBottom ? parent.bottom : undefined
    }
    spacing: win.gap
  }
}

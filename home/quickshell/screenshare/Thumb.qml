import Quickshell.Wayland
import QtQuick
import "../widgets"

// Live (or one-shot) capture of a screen or window, letterboxed into its box.
// While there's no frame (capture unsupported, window unmapped, first frame
// not in yet) it shows `fallback` -- a glyph tile like the mockup's.
Rectangle {
  id: thumb

  property var source: null           // ShellScreen | Toplevel | null
  property bool live: false
  property string glyph: "app-window"
  property color accent: Pal.dim
  property string iconPath: ""        // app icon file, preferred over glyph
  property string badge: ""           // bottom-right label (e.g. "ws 2")
  property bool showBar: false        // faux title bar on the fallback tile

  color: Pal.deep
  radius: 4
  clip: true
  border.width: 1
  border.color: "#3e4451"

  ScreencopyView {
    id: view
    anchors.centerIn: parent
    captureSource: thumb.source
    live: thumb.live
    paintCursor: false
    visible: hasContent
    readonly property real k: sourceSize.width > 0 && sourceSize.height > 0
      ? Math.min((thumb.width - 2) / sourceSize.width, (thumb.height - 2) / sourceSize.height) : 1
    width: sourceSize.width * k
    height: sourceSize.height * k
    Component.onCompleted: if (!thumb.live && thumb.source) Qt.callLater(view.captureFrame)
  }

  // fallback tile
  Item {
    anchors.fill: parent
    visible: !view.hasContent
    Rectangle {
      visible: thumb.showBar
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 8
      color: Pal.edge
      Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 2; color: thumb.accent }
    }
    Image {
      id: appIcon
      visible: thumb.iconPath !== "" && status === Image.Ready
      anchors.centerIn: parent
      width: 32; height: 32
      source: thumb.iconPath
      sourceSize: Qt.size(64, 64)
      fillMode: Image.PreserveAspectFit
      opacity: 0.9
    }
    PhIcon {
      visible: !appIcon.visible
      anchors.centerIn: parent
      name: thumb.glyph
      font.pixelSize: 26
      color: thumb.accent
      opacity: 0.85
    }
  }

  Mono {
    visible: thumb.badge !== ""
    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 5; bottomMargin: 3 }
    text: thumb.badge
    font.pixelSize: 10
    color: Pal.muted
  }
}

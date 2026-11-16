import QtQuick
import Quickshell.Wayland

// One whole desktop at its real size (screenW x screenH): the wallpaper, and each
// window of the workspace where it really sits. It is shown small by scaling the
// whole item, so no layout maths is needed and the same item can grow back to full
// size. Window pictures are taken once and never refreshed.
Item {
  id: desk

  property var spec: null            // a desk from Layout.rowsOf(): { windows: [...] }
  property real screenW: 2256
  property real screenH: 1504
  property url wallpaper: ""
  property var captureFor: function (address) { return null; }

  width: screenW
  height: screenH
  transformOrigin: Item.TopLeft

  Rectangle { anchors.fill: parent; color: "#1e2127" }

  Image {
    anchors.fill: parent
    visible: desk.wallpaper.toString() !== ""
    source: desk.wallpaper
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    // One decode at screen size, shared by every desk.
    sourceSize: Qt.size(desk.screenW, desk.screenH)
  }

  Repeater {
    model: desk.spec ? desk.spec.windows : []

    delegate: Item {
      id: win
      required property var modelData
      x: modelData.x
      y: modelData.y
      width: modelData.w
      height: modelData.h

      // Shown until its picture arrives (and if one never does): a clearly visible
      // box with the app's name, sized for a desktop that is displayed small.
      Rectangle { anchors.fill: parent; color: "#323945"; border.width: 4; border.color: "#6b7385" }
      Text {
        anchors.centerIn: parent
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: win.modelData.cls || win.modelData.title
        color: "#abb2bf"
        font.family: "JetBrains Mono"
        font.pixelSize: 84
        visible: !picture.hasContent
      }

      ScreencopyView {
        id: picture
        anchors.fill: parent
        captureSource: desk.captureFor(win.modelData.address)
        live: false
        paintCursor: false
        Component.onCompleted: if (captureSource) Qt.callLater(picture.captureFrame)
      }
    }
  }
}

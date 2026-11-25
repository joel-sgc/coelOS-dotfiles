import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

// ===== WALLPAPER =====
// Draws the wallpaper on every screen (Background layer). `coel-set-wallpaper`
// (home/wallpaper.nix) writes the image path to $XDG_RUNTIME_DIR/coel-wallpaper
// and calls `ipc call wallpaper reload`. A new image fades in over the old one
// while zooming from 104% and sharpening from a blur (the bar mockup's swap).
Scope {
  id: root

  property string path: ""

  FileView {
    id: state
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/coel-wallpaper"
    printErrors: false
    onLoaded: root.path = text().trim()
  }

  IpcHandler {
    target: "wallpaper"
    function reload(): void { state.reload(); }
  }

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      anchors { top: true; left: true; right: true; bottom: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "coel-wallpaper"

      readonly property url target: root.path === "" ? "" : "file://" + root.path.split("/").map(encodeURIComponent).join("/")
      // Decode at the screen's size, not the image's.
      readonly property size decodeSize: Qt.size(Math.ceil(width * devicePixelRatio), Math.ceil(height * devicePixelRatio))

      onTargetChanged: swap()
      Component.onCompleted: swap()

      function swap() {
        if (target.toString() === "" || target === incoming.source) return;
        // Interrupted mid-swap: settle on the image that was coming in.
        if (anim.running) {
          anim.stop();
          base.source = incoming.source;
        }
        incoming.opacity = 0;
        incoming.source = target;
        if (incoming.status === Image.Ready) start();
      }
      function start() {
        if (Globals.eyeCandyOff) { base.source = incoming.source; return; }
        incoming.opacity = 0;
        anim.restart();
      }

      Image {
        id: base
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: win.decodeSize
      }

      Image {
        id: incoming
        property real blurAmount: 0
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: win.decodeSize
        opacity: 0
        onStatusChanged: if (status === Image.Ready && source !== base.source) win.start()
        layer.enabled: anim.running
        layer.effect: MultiEffect {
          autoPaddingEnabled: false
          blurEnabled: true
          blurMax: 32
          blur: incoming.blurAmount
        }
      }

      ParallelAnimation {
        id: anim
        readonly property var curve: [0.22, 1, 0.36, 1, 1, 1]
        NumberAnimation { target: incoming; property: "opacity"; from: 0; to: 1; duration: 750; easing.type: Easing.BezierSpline; easing.bezierCurve: anim.curve }
        NumberAnimation { target: incoming; property: "scale"; from: 1.04; to: 1; duration: 750; easing.type: Easing.BezierSpline; easing.bezierCurve: anim.curve }
        // Sharp by 55% of the way through.
        NumberAnimation { target: incoming; property: "blurAmount"; from: 1; to: 0; duration: 412; easing.type: Easing.BezierSpline; easing.bezierCurve: anim.curve }
        // The incoming image stays on top until the base has loaded the same one.
        onFinished: base.source = incoming.source
      }
    }
  }
}

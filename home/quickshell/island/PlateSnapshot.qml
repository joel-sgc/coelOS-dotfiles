import QtQuick
import ".."
import "Parts.js" as P

// A frame from the printer's camera. `src` is a file:// URL to the latest JPEG
// (see sources/PrinterSource.qml); with none yet, a flat build plate stands in.
// `label` (e.g. "CAM · 14:12") and `badge`/`badgeColor` only draw when wide.
Rectangle {
  id: snap
  property string src: ""
  property string label: ""
  property string badge: ""
  property color badgeColor: P.C.gr

  readonly property bool wide: width > 60
  // The camera's own shape (P1S: 1280x720), measured from the frame; 16:9 until
  // one has loaded. Users size one dimension and derive the other from this.
  readonly property real aspect: img.status === Image.Ready && img.implicitHeight > 0
    ? img.implicitWidth / img.implicitHeight : 16 / 9
  color: "#1e2127"
  radius: Globals.eyeCandyOff ? 0 : (wide ? 6 : 3)
  clip: true

  // placeholder plate
  Rectangle {
    visible: !img.visible
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: parent.height * 0.18
    color: P.C.sf
  }
  Rectangle {
    visible: !img.visible
    x: parent.width * 0.36
    width: parent.width * 0.28
    height: parent.height * 0.2
    y: parent.height * 0.82 - height
    color: P.C.or
    opacity: 0.85
  }

  Image {
    id: img
    anchors.fill: parent
    visible: snap.src !== "" && status === Image.Ready
    source: snap.src
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    smooth: true
  }

  Text {
    visible: snap.wide && snap.label !== ""
    x: 6; y: 4
    text: snap.label
    color: P.C.mu
    font.family: "JetBrains Mono"
    font.pixelSize: Math.max(8, Math.min(10, snap.width / 34))
  }

  Rectangle {
    visible: snap.wide && snap.badge !== ""
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 4
    width: badgeText.implicitWidth + 10
    height: badgeText.implicitHeight + 4
    radius: Globals.eyeCandyOff ? 0 : 3
    color: snap.badgeColor
    Text {
      id: badgeText
      anchors.centerIn: parent
      text: snap.badge
      color: P.C.bg
      font.family: "JetBrains Mono"
      font.pixelSize: Math.max(8, Math.min(10, snap.width / 34))
    }
  }
}

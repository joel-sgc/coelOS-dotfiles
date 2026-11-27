import QtQuick
import QtQuick.Shapes
import ".."
import "../widgets"

// The big progress ring (Desktop Board `bigRing`): `value` 0..100 of `tint`
// over a dark track, a faint halo, and whatever children sit in the middle.
Item {
  id: ring
  property real value: 0
  property color tint: Pal.red
  property int size: 64
  default property alias content: middle.data

  implicitWidth: size
  implicitHeight: size
  readonly property real thick: Math.max(4, size / 26)

  Rectangle {   // halo: a 6 px band of tint @ 8% just outside the ring
    anchors.centerIn: parent
    width: ring.size + 12; height: width
    radius: width / 2
    color: "transparent"
    border.width: 6
    border.color: Qt.rgba(ring.tint.r, ring.tint.g, ring.tint.b, 0.08)
  }
  Shape {
    anchors.fill: parent
    layer.enabled: true
    layer.samples: 4
    ShapePath {
      strokeColor: Pal.track
      fillColor: "transparent"
      strokeWidth: ring.thick
      PathAngleArc {
        centerX: ring.size / 2; centerY: ring.size / 2
        radiusX: (ring.size - ring.thick) / 2; radiusY: radiusX
        startAngle: 0; sweepAngle: 360
      }
    }
    ShapePath {
      strokeColor: ring.tint
      fillColor: "transparent"
      strokeWidth: ring.thick
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: ring.size / 2; centerY: ring.size / 2
        radiusX: (ring.size - ring.thick) / 2; radiusY: radiusX
        startAngle: -90
        sweepAngle: 3.6 * Math.max(0, Math.min(100, ring.value))
      }
    }
  }
  Item { id: middle; anchors.centerIn: parent; width: childrenRect.width; height: childrenRect.height }
}

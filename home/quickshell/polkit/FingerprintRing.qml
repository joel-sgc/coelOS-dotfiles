import QtQuick
import QtQuick.Shapes
import "../widgets"

// Round fingerprint button: a track ring, an optional progress/result arc on
// top of it, the glyph in the middle and (while listening) a faint halo.
Item {
  id: ring

  property int diameter: 84
  property real thickness: 3
  property real progress: 0          // 0..1 of the colored arc
  property color arcColor: Pal.blue
  property color glyphColor: Pal.dim
  property bool halo: false
  property int glyphSize: 40
  signal clicked()

  implicitWidth: diameter
  implicitHeight: diameter

  Rectangle {
    anchors.centerIn: parent
    width: ring.diameter + 12; height: width; radius: width / 2
    color: Qt.rgba(97 / 255, 175 / 255, 239 / 255, 0.08)
    visible: ring.halo
  }

  Shape {
    anchors.fill: parent
    layer.enabled: true
    layer.samples: 4
    ShapePath {
      strokeColor: "#3e4451"
      fillColor: "transparent"
      strokeWidth: ring.thickness
      PathAngleArc {
        centerX: ring.diameter / 2; centerY: ring.diameter / 2
        radiusX: (ring.diameter - ring.thickness) / 2; radiusY: radiusX
        startAngle: 0; sweepAngle: 360
      }
    }
    ShapePath {
      strokeColor: ring.arcColor
      fillColor: "transparent"
      strokeWidth: ring.thickness
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: ring.diameter / 2; centerY: ring.diameter / 2
        radiusX: (ring.diameter - ring.thickness) / 2; radiusY: radiusX
        startAngle: -90; sweepAngle: 360 * ring.progress
      }
    }
  }

  PhIcon {
    anchors.centerIn: parent
    name: "fingerprint"
    font.pixelSize: ring.glyphSize
    color: ring.glyphColor
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: ring.clicked()
  }
}

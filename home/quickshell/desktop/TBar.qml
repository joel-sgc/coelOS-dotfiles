import QtQuick
import ".."
import "../widgets"

// A flat progress track (Desktop Board `tbar`): `value` 0..100.
Rectangle {
  id: bar
  property real value: 0
  property color fill: Pal.green
  implicitHeight: 6
  radius: Globals.eyeCandyOff ? 0 : 1
  color: Pal.track
  clip: true
  Rectangle {
    width: parent.width * Math.max(0, Math.min(100, bar.value)) / 100
    height: parent.height
    color: bar.fill
    Behavior on width {
      enabled: !Globals.eyeCandyOff
      NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
    }
  }
}

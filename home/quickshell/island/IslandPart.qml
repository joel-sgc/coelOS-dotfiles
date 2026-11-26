import QtQuick
import QtQuick.Shapes
import ".."
import "../sysPanel/Phosphor.js" as Phosphor
import "Parts.js" as P

// Draws one part (see Parts.js) at its natural size.
Item {
  id: partRoot
  property var part: ({ k: "space", w: 0 })

  implicitWidth: loader.item ? loader.item.implicitWidth : 0
  implicitHeight: loader.item ? loader.item.implicitHeight : 0

  readonly property string fillFamily: Qt.fontFamilies().indexOf("Phosphor-Fill") >= 0 ? "Phosphor-Fill" : "Phosphor"

  Loader {
    id: loader
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: ({
      icon: iconC, text: textC, ring: ringC, eq: eqC, dot: dotC, thumb: thumbC, space: spaceC
    })[partRoot.part.k] || spaceC
  }

  Component {
    id: iconC
    Text {
      text: Phosphor.icon(partRoot.part.name)
      color: partRoot.part.color
      font.family: partRoot.part.fill ? partRoot.fillFamily : "Phosphor"
      font.pixelSize: partRoot.part.size
    }
  }

  Component {
    id: textC
    Item {
      implicitWidth: partRoot.part.maxWidth > 0 ? Math.min(label.implicitWidth, partRoot.part.maxWidth) : label.implicitWidth
      implicitHeight: label.implicitHeight
      Text {
        id: label
        width: parent.implicitWidth
        text: partRoot.part.s
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        color: partRoot.part.color
        font.family: "JetBrains Mono"
        font.pixelSize: partRoot.part.size
      }
    }
  }

  Component {
    id: ringC
    Item {
      readonly property int s: partRoot.part.size
      readonly property real w: 2
      implicitWidth: s
      implicitHeight: s
      Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4
        ShapePath {
          strokeColor: P.C.sf
          fillColor: "transparent"
          strokeWidth: 2
          PathAngleArc {
            centerX: partRoot.part.size / 2; centerY: centerX
            radiusX: (partRoot.part.size - 2) / 2; radiusY: radiusX
            startAngle: 0; sweepAngle: 360
          }
        }
        ShapePath {
          strokeColor: partRoot.part.color
          fillColor: "transparent"
          strokeWidth: 2
          capStyle: ShapePath.RoundCap
          PathAngleArc {
            centerX: partRoot.part.size / 2; centerY: centerX
            radiusX: (partRoot.part.size - 2) / 2; radiusY: radiusX
            startAngle: -90
            sweepAngle: 3.6 * Math.max(0, Math.min(100, partRoot.part.p))
          }
        }
      }
    }
  }

  // Three bars that move with the music; frozen when paused or eye candy is off.
  Component {
    id: eqC
    Item {
    implicitWidth: 10
    implicitHeight: 11
    Row {
      spacing: 2
      height: 11
      Repeater {
        model: [0.55, 1, 0.75]
        Rectangle {
          id: bar
          required property real modelData
          required property int index
          width: 2
          radius: 1
          height: Math.round(modelData * 11)
          anchors.bottom: parent.bottom
          color: partRoot.part.color
          readonly property bool moving: partRoot.part.on && !Globals.eyeCandyOff
          SequentialAnimation on height {
            running: bar.moving
            loops: Animation.Infinite
            onRunningChanged: if (!running) bar.height = Math.round(bar.modelData * 11)
            PauseAnimation { duration: bar.index * 130 }
            NumberAnimation { to: 3; duration: 380; easing.type: Easing.InOutSine }
            NumberAnimation { to: 11; duration: 420; easing.type: Easing.InOutSine }
            NumberAnimation { to: Math.round(bar.modelData * 11); duration: 300; easing.type: Easing.InOutSine }
          }
        }
      }
    }
    }
  }

  Component {
    id: dotC
    Rectangle {
      id: d
      implicitWidth: partRoot.part.size
      implicitHeight: partRoot.part.size
      radius: width / 2
      color: partRoot.part.color
      SequentialAnimation on opacity {
        running: partRoot.part.blink && !Globals.eyeCandyOff
        loops: Animation.Infinite
        onRunningChanged: if (!running) d.opacity = 1
        NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
      }
    }
  }

  Component {
    id: thumbC
    PlateSnapshot {
      // Height is what the row allows; width follows the camera's aspect.
      implicitWidth: Math.round(partRoot.part.h * aspect)
      implicitHeight: partRoot.part.h
      src: partRoot.part.src
    }
  }

  Component {
    id: spaceC
    Item { implicitWidth: partRoot.part.w || 0; implicitHeight: 1 }
  }
}

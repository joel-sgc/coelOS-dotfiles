import QtQuick
import ".."
import "../.."
import "../Parts.js" as P

// The printer's card (hover/click its chip): camera, progress, temps, controls.
Column {
  id: card
  property var source
  property var engine
  property var screen

  readonly property var s: source
  readonly property bool paused: !!s && s.status === "paused"
  readonly property color tint: paused ? P.C.or : P.C.cy

  width: 420
  spacing: 10

  CardHead {
    width: parent.width
    icon: "printer"
    tint: P.C.cy
    title: card.s ? card.s.name : ""
    sub: card.s ? "· " + card.s.statusText : ""
    trailing: card.s ? card.s.file : ""
  }

  PlateSnapshot {
    width: parent.width
    height: Math.round(width / aspect)
    src: card.s ? card.s.snapshot : ""
    label: card.s ? card.s.snapshotLabel : "CAM"
  }

  Item {
    width: parent.width
    height: big.implicitHeight
    Row {
      spacing: 10
      Text {
        id: big
        text: (card.s ? card.s.pct : 0) + "%"
        font.family: "JetBrains Mono"
        font.pixelSize: 18
        font.weight: Font.Medium
        color: card.tint
      }
      Text {
        anchors.baseline: big.baseline
        text: card.s ? "layer " + card.s.layer + " / " + card.s.totalLayers : ""
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        color: P.C.mu
      }
    }
    Text {
      x: parent ? parent.width - width : 0
      y: big.baselineOffset - baselineOffset
      text: card.s ? card.s.remainingText : ""
      font.family: "JetBrains Mono"
      font.pixelSize: 12
      color: P.C.fg
    }
  }

  Rectangle {
    width: parent.width
    height: 4
    radius: 2
    color: P.C.sf
    Rectangle {
      width: parent.width * (card.s ? card.s.pct : 0) / 100
      height: parent.height
      radius: 2
      color: card.tint
      Behavior on width {
        enabled: !Globals.eyeCandyOff
        NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: P.morph }
      }
    }
  }

  Grid {
    columns: 4
    columnSpacing: 12
    rowSpacing: 2
    Repeater {
      // Fixed count, values by index (an array model rebuilds on every update).
      model: 8
      Text {
        required property int index
        readonly property var cells: card.s ? [
          "nozzle", card.s.nozzleText, "bed", card.s.bedText,
          "speed", card.s.speed, "fan", card.s.fan + "%"
        ] : []
        text: String(cells[index] || "")
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        color: index % 2 === 0 ? P.C.mu : P.C.fg
      }
    }
  }

  Item {
    width: parent.width
    height: 22
    Row {
      spacing: 6
      IslandButton {
        enabled: !card.s.stale
        icon: card.paused ? "play" : "pause"
        iconFill: true
        text: card.paused ? "resume" : "pause"
        onClicked: card.paused ? card.s.resume() : card.s.pause()
      }
      IslandButton {
        // Two clicks: a stray click must never kill a print.
        property bool armed: false
        enabled: !card.s.stale
        text: armed ? "really stop?" : "stop"
        tint: P.C.red
        primary: armed
        onClicked: {
          if (armed) { armed = false; card.s.stop(); }
          else { armed = true; disarm.restart(); }
        }
        Timer { id: disarm; interval: 3000; onTriggered: parent.armed = false }
      }
    }
    IslandButton {
      anchors.right: parent.right
      text: "Bambu Studio"
      icon: "arrow-square-out"
      tint: P.C.mu
      onClicked: { card.engine.closeCard(); card.s.openStudio(); }
    }
  }
}

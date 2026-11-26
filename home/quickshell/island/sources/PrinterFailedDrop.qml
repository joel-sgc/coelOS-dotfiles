import QtQuick
import ".."
import "../Parts.js" as P

// Detail under the "Print failed" interrupt: the plate as the camera last saw
// it, the printer's reason, and what to do about it.
Row {
  id: drop
  property var source
  property var engine
  property var screen
  property var entry

  readonly property var s: source
  spacing: 12
  width: 440

  PlateSnapshot {
    width: 150
    height: Math.round(width / aspect)
    src: drop.s ? drop.s.snapshot : ""
    label: drop.s ? drop.s.snapshotLabel : ""
    badge: "failed"
    badgeColor: P.C.err
  }

  Column {
    width: drop.width - 150 - drop.spacing
    spacing: 8
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      lineHeight: 1.3
      text: drop.s ? drop.s.errorText : ""
      textFormat: Text.PlainText
      font.family: "JetBrains Mono"
      font.pixelSize: 12
      color: P.C.fg
    }
    Flow {
      width: parent.width
      spacing: 6
      IslandButton {
        text: "resume"
        enabled: !drop.s.stale
        visible: !!drop.s && drop.s.status === "paused"
        onClicked: drop.s.resume()
      }
      IslandButton {
        property bool armed: false
        text: armed ? "really cancel?" : "cancel print"
        enabled: !drop.s.stale
        tint: P.C.err
        primary: armed
        visible: !!drop.s && drop.s.status === "paused"
        onClicked: {
          if (armed) { armed = false; drop.s.stop(); }
          else { armed = true; disarm.restart(); }
        }
        Timer { id: disarm; interval: 3000; onTriggered: parent.armed = false }
      }
      IslandButton {
        text: "dismiss"
        tint: P.C.mu
        onClicked: drop.engine.dismissInterrupt("print-failed")
      }
    }
  }
}

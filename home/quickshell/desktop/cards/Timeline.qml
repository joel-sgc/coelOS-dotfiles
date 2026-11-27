import QtQuick
import "../../widgets"

// Today from 07:00 to 22:00 (Desktop Board `timeline`): a track with each
// event as a colored block, a marker at now, hour labels underneath.
Item {
  id: tl
  property var events: []   // {start, end (ms), color}
  property real now: Date.now()
  readonly property real from: 7
  readonly property real to: 22

  implicitHeight: 34
  function fx(ms) {
    const d = new Date(ms), h = d.getHours() + d.getMinutes() / 60;
    return Math.max(0, Math.min(1, (h - from) / (to - from))) * width;
  }
  Rectangle { y: 10; width: parent.width; height: 6; radius: 1; color: Pal.track }
  Repeater {
    model: tl.events.length
    Rectangle {
      required property int index
      readonly property var e: tl.events[index] || ({ start: 0, end: 0 })
      y: 8; height: 10; radius: 2
      x: tl.fx(e.start)
      width: Math.max(3, tl.fx(e.end) - tl.fx(e.start))
      color: e.color || Pal.blue
    }
  }
  Rectangle { visible: tl.now > 0; x: tl.fx(tl.now) - 1; y: 2; width: 2; height: 20; radius: 1; color: Pal.fg }
  Repeater {
    model: [7, 10, 13, 16, 19, 22]
    Mono {
      required property var modelData
      x: Math.max(0, Math.min(tl.width - width, (modelData - tl.from) / (tl.to - tl.from) * tl.width - width / 2))
      y: 22
      text: String(modelData).padStart(2, "0")
      font.pixelSize: 10
      color: Pal.muted
    }
  }
}

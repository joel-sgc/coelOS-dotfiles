import QtQuick
import Quickshell.Wayland
import ".."

// ===== WORKSPACE OVERVIEW =====
// Your desktop shrinks into a stack of five miniature desktops, one per row of the
// workspace grid, each as you left it (its other workspaces sit beside it; scroll
// a row sideways to see them). The wallpaper stays behind, dimmed. Up/Down or the
// mouse moves the selector over the rows; Enter or a click takes you to that row,
// on the column it was left on, growing that desktop back to full size. Escape or
// a click on the background puts your desktop back.
//
// `t` runs the animation: 0 is your real desktop, 1 is the overview. Opening starts
// from a picture of the actual screen, so nothing visibly changes before it shrinks.
// Presentational: Overview.qml supplies the data and makes the Hyprland call.
FocusScope {
  id: ov

  property var rows: []                  // Layout.rowsOf()
  property bool dataReady: false
  property real screenW: 2256
  property real screenH: 1504
  property var screenSource: null        // the screen, for the opening picture
  property url wallpaper: ""
  property var captureFor: function (address) { return null; }
  property color accent: "#61afef"
  property color mutedColor: "#5c6370"

  readonly property int currentRow: {
    for (let i = 0; i < rows.length; i++) if (rows[i].current) return i;
    return 0;
  }
  property int selected: currentRow

  // 0 = your desktop, 1 = the overview.
  property real t: 0
  property string phase: "waiting"       // waiting -> open -> closing
  property int growRow: -1               // row whose desktop grows to fill the screen on the way out

  signal rowChosen(int row)
  signal finished()

  readonly property real pad: 40
  readonly property real gap: 12
  readonly property real labelWidth: 38
  readonly property real stripGap: 8
  readonly property real rowHeight: Math.max(1, (height - 2 * pad - Math.max(0, rows.length - 1) * gap) / Math.max(1, rows.length))
  readonly property real deskH: Math.max(1, rowHeight - 16)
  readonly property real deskW: deskH * screenW / screenH
  readonly property real shrink: deskW / screenW

  function repIndex(row) {
    const desks = rows[row] ? rows[row].desks : [];
    for (let i = 0; i < desks.length; i++) if (desks[i].rep) return i;
    return 0;
  }
  // Where a row's representative desk sits on screen right now.
  function slotX(row) {
    const strip = stripFor(row);
    return pad + labelWidth + repIndex(row) * (deskW + stripGap) - (strip ? strip.contentX : 0);
  }
  function slotY(row) { return pad + row * (rowHeight + gap) + 8; }
  function stripFor(row) { const r = rowRepeater.itemAt(row); return r ? r.strip : null; }

  function start() {
    if (phase !== "waiting") return;
    phase = "open";
    anim.from = 0; anim.to = 1; anim.restart();
  }
  function closeTo(row) {
    if (phase === "closing") return;
    phase = "closing";
    growRow = row !== currentRow ? row : -1;
    anim.from = t; anim.to = 0; anim.restart();
  }
  function choose(row) {
    if (phase !== "open") return;
    if (row !== currentRow) rowChosen(row);
    closeTo(row);
  }
  // Put your desktop back. Before the opening picture has arrived there is nothing
  // to zoom, so it just ends.
  function dismiss() {
    if (phase === "open") closeTo(currentRow);
    else if (phase === "waiting") finished();
  }

  // Begin as soon as there is something to show and the opening picture is in.
  readonly property bool ready: dataReady && (snap.hasContent || fallback.running === false)
  onReadyChanged: if (ready) start()
  Timer { id: fallback; interval: 350; running: true }   // do not wait forever for the picture

  NumberAnimation { id: anim; target: ov; property: "t"; duration: 260; easing.type: Easing.OutCubic
                    onFinished: if (ov.phase === "closing") ov.finished() }

  focus: true
  Keys.onEscapePressed: ov.dismiss()
  Keys.onUpPressed: ov.selected = Math.max(0, ov.selected - 1)
  Keys.onDownPressed: ov.selected = Math.min(ov.rows.length - 1, ov.selected + 1)
  Keys.onReturnPressed: ov.choose(ov.selected)
  Keys.onEnterPressed: ov.choose(ov.selected)

  // Wallpaper, dimmed, fading in behind everything.
  Item {
    anchors.fill: parent
    opacity: ov.t
    Rectangle { anchors.fill: parent; color: "#1a1d23" }
    Image {
      anchors.fill: parent
      visible: ov.wallpaper.toString() !== ""
      source: ov.wallpaper
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize: Qt.size(ov.screenW, ov.screenH)
    }
    Rectangle { anchors.fill: parent; color: "#101216"; opacity: 0.62 }
    MouseArea { anchors.fill: parent; onClicked: ov.dismiss() }
  }

  Repeater {
    id: rowRepeater
    model: ov.rows

    delegate: Item {
      id: rowItem
      required property var modelData
      required property int index
      readonly property bool selected: index === ov.selected
      readonly property alias strip: strip
      x: ov.pad
      y: ov.pad + index * (ov.rowHeight + ov.gap)
      width: ov.width - 2 * ov.pad
      height: ov.rowHeight
      z: ov.growRow === index ? 10 : 0

      Rectangle {
        anchors.fill: parent
        radius: Globals.eyeCandyOff ? 0 : 8
        color: rowItem.selected ? "#ffffff" : "transparent"
        opacity: ov.t * 0.07
        border.width: 0
      }
      Rectangle {
        anchors.fill: parent
        radius: Globals.eyeCandyOff ? 0 : 8
        color: "transparent"
        border.width: rowItem.selected ? 1 : 0
        border.color: ov.accent
        opacity: ov.t
      }

      Text {
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        text: rowItem.modelData.label
        color: rowItem.modelData.current ? ov.accent : ov.mutedColor
        opacity: ov.t * (rowItem.modelData.current || rowItem.selected ? 1 : 0.6)
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }

      // Only the desktops in view exist, and each window picture is taken once.
      ListView {
        id: strip
        x: ov.labelWidth
        y: 8
        width: parent.width - ov.labelWidth - 8
        height: ov.deskH
        orientation: ListView.Horizontal
        spacing: ov.stripGap
        clip: ov.growRow !== rowItem.index      // let the growing desktop out of its strip
        interactive: contentWidth > width && ov.phase === "open"
        boundsBehavior: Flickable.StopAtBounds
        model: rowItem.modelData.desks
        Component.onCompleted: positionViewAtIndex(ov.repIndex(rowItem.index), ListView.Center)

        delegate: Item {
          id: slot
          required property var modelData
          width: ov.deskW
          height: ov.deskH
          readonly property bool grows: ov.growRow === rowItem.index && modelData.rep
          z: grows ? 2 : 1
          opacity: grows ? 1 : ov.t * (modelData.rep ? 1 : 0.88)

          // Where this desktop is on screen, for growing it to full size.
          readonly property point origin: ov.growRow >= 0 ? slot.mapToItem(ov, 0, 0) : Qt.point(0, 0)

          Desk {
            spec: slot.modelData
            screenW: ov.screenW
            screenH: ov.screenH
            wallpaper: ov.wallpaper
            captureFor: ov.captureFor
            // Small in its slot; growing: out to the full screen as t falls to 0.
            scale: slot.grows ? ov.shrink + (1 - ov.shrink) * (1 - ov.t) : ov.shrink
            x: slot.grows ? -slot.origin.x * (1 - ov.t) : 0
            y: slot.grows ? -slot.origin.y * (1 - ov.t) : 0
          }

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Globals.eyeCandyOff ? 0 : 3
            border.width: slot.modelData.rep && rowItem.selected ? 2 : 1
            border.color: slot.modelData.rep && rowItem.selected ? ov.accent : "#3e4451"
            visible: !slot.grows || ov.t > 0.2
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: ov.phase === "open"
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: ov.selected = rowItem.index
        onClicked: ov.choose(rowItem.index)
      }
    }
  }

  // Your real screen, shrinking into its row (and growing back on the way out).
  Item {
    id: hero
    visible: ov.phase !== "waiting" && ov.growRow < 0
    width: ov.screenW
    height: ov.screenH
    transformOrigin: Item.TopLeft
    scale: ov.shrink + (1 - ov.shrink) * (1 - ov.t)
    x: ov.slotX(ov.currentRow) * ov.t
    y: ov.slotY(ov.currentRow) * ov.t
    // Settles into the row's own desktop at the end instead of popping.
    opacity: ov.t > 0.8 ? (1 - ov.t) / 0.2 : 1

    Desk {   // stand-in if the picture of the screen could not be taken
      spec: ov.rows.length ? ov.rows[ov.currentRow].desks[ov.repIndex(ov.currentRow)] : null
      screenW: ov.screenW; screenH: ov.screenH; wallpaper: ov.wallpaper; captureFor: ov.captureFor
      visible: !snap.hasContent
    }
    ScreencopyView {
      id: snap
      anchors.fill: parent
      captureSource: ov.screenSource
      live: false
      paintCursor: false
      Component.onCompleted: if (captureSource) captureFrame()
    }
  }
}

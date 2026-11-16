import QtQuick
import QtQuick.Shapes
import Quickshell.Wayland
import ".."

// ===== WORKSPACE OVERVIEW =====
// (Design: example/Workspace Overview.dc.html.) The five rows of the workspace grid
// are laid out as a map: row labels down the left, each row a strip of miniature
// desktops (its workspaces that have windows, plus the one it returns to), and the
// strip slides to keep the selected desktop centred. Arrows / scroll / mouse move
// the selector, Enter or a click goes there; typing searches window titles and
// classes. Escape clears the search, then puts your desktop back.
//
// `t` runs the animation: 0 is your real desktop filling the screen, 1 is the map.
// The whole map is one item that is scaled and slid so that one desktop fills the
// screen at t = 0: opening zooms out of your desktop, and choosing a desktop zooms
// into that one. Presentational: Overview.qml supplies the data and makes the
// Hyprland call.
FocusScope {
  id: ov

  property var rows: []                  // Layout.rowsOf()
  property bool dataReady: false
  property real screenW: 2256
  property real screenH: 1504
  property var screenSource: null        // the screen, for the picture of your desktop
  property url wallpaper: ""
  property var captureFor: function (address) { return null; }

  readonly property int currentRow: {
    for (let i = 0; i < rows.length; i++) if (rows[i].current) return i;
    return 0;
  }

  // Selector, and the desktop the map is zoomed onto (your own until you leave).
  property int selRow: 0
  property int selIdx: 0
  property int zoomRow: 0
  property int zoomIdx: 0
  property string query: ""

  // 0 = your desktop, 1 = the map.
  property real t: 0
  property string phase: "waiting"       // waiting -> open -> closing (drag: following your fingers)
  property bool driven: false            // opened by a swipe that is still going: follow it
  property real dragT: 0                 // where the fingers have taken t (0..1)

  // row, workspace id, and whether it is the desktop that row returns to anyway.
  signal chosen(int row, int id, bool rep)
  signal finished()

  // ---- geometry (the design is authored for 1280 wide; u scales it to the screen) ----
  // 0.78: the design filled the screen with its map; a little smaller leaves air
  // around it and shows more of each row.
  readonly property real u: Math.min(width / 1280, height / 800) * 0.78
  readonly property real tileW: 190 * u
  readonly property real tileH: tileW * screenH / screenW
  readonly property real shrink: tileW / screenW
  readonly property real pitchX: 204 * u
  readonly property real pitchY: tileH + 20.5 * u
  // The map sits in a stage centred on the screen; the rest is plain background.
  readonly property real stageW: Math.min(width - 80 * u, 1180 * u)
  readonly property real ox: (width - stageW) / 2
  readonly property real x0: 84 * u
  readonly property real y0: 60 * u
  readonly property real visW: stageW - x0 - 24 * u
  // The rows are centred on the screen; the search pill and key hints hug its edges.
  readonly property real rowsH: 4 * pitchY + tileH + 20 * u
  readonly property real rowsTop: Math.max(0, (height - rowsH) / 2)
  readonly property real radius: Globals.eyeCandyOff ? 0 : 9 * u
  readonly property real zoomS: screenW / tileW
  readonly property real chrome: Math.max(0, Math.min(1, (t - 0.35) / 0.65))

  readonly property color cBg: "#282c34"          // the panel's own background
  readonly property color cTile: "#21252b"
  readonly property color cRing: "#3b414d"
  readonly property color cShade: "#14161a"
  readonly property color cPanel: "#21252b"
  readonly property color cFg: "#abb2bf"
  readonly property color cMute: "#5c6370"
  readonly property color cDim: "#3e4451"
  readonly property color cAccent: "#61afef"
  readonly property color cGreen: "#89ca78"
  readonly property color cYellow: "#e5c07b"
  readonly property color cRed: "#ef596f"

  function desksOf(row) { return rows[row] ? rows[row].desks : []; }
  function repIndex(row) {
    const desks = desksOf(row);
    for (let i = 0; i < desks.length; i++) if (desks[i].rep) return i;
    return 0;
  }
  function rowAt(row) { rowRepeater.count; return rowRepeater.itemAt(row); }
  // Where a desktop sits on screen (in the map's own, unzoomed coordinates).
  function tileX(row, idx) { const r = rowAt(row); return ox + x0 + idx * pitchX - (r ? r.off : 0); }
  function tileY(row) { return rowsTop + row * pitchY; }

  function deskMatches(desk, q) {
    const out = [];
    desk.windows.forEach(w => {
      if ((w.name + " " + w.cls + " " + w.title).toLowerCase().indexOf(q) >= 0) out.push(w.address);
    });
    return out;
  }
  // Every desktop with a match, in reading order: [{ row, idx }].
  readonly property var hits: {
    const q = query.trim().toLowerCase();
    const out = [];
    if (q === "") return out;
    for (let r = 0; r < rows.length; r++) {
      const desks = rows[r].desks;
      for (let i = 0; i < desks.length; i++) if (deskMatches(desks[i], q).length) out.push({ row: r, idx: i });
    }
    return out;
  }
  readonly property int hitWindows: {
    const q = query.trim().toLowerCase();
    let n = 0;
    if (q === "") return 0;
    for (let r = 0; r < rows.length; r++)
      for (const d of rows[r].desks) n += deskMatches(d, q).length;
    return n;
  }
  readonly property int totalWindows: {
    let n = 0;
    for (const r of rows) for (const d of r.desks) n += d.windows.length;
    return n;
  }
  // Jump to the first desktop with a match (after the bindings above have settled).
  onQueryChanged: {
    if (field.text !== query) field.text = query;
    Qt.callLater(ov.jumpToHit);
  }
  function jumpToHit() {
    if (ov.hits.length) { ov.selRow = ov.hits[0].row; ov.selIdx = ov.hits[0].idx; }
  }
  function move(dr, dc) {
    if (phase !== "open" || !rows.length) return;
    let r = selRow, i = selIdx;
    if (dc) i = Math.max(0, Math.min(desksOf(r).length - 1, i + dc));
    if (dr) {
      const nr = Math.max(0, Math.min(rows.length - 1, r + dr));
      if (nr === r) return;
      r = nr;
      i = Math.min(i, desksOf(r).length - 1);
    }
    selRow = r; selIdx = i;
  }

  function start(from) {
    if (phase !== "waiting") return;
    selRow = zoomRow = currentRow;
    selIdx = zoomIdx = repIndex(currentRow);
    phase = "open";
    // Never start so far along that there is nothing left to see.
    anim.from = Math.min(from || 0, 0.5); anim.to = 1; anim.restart();
  }

  // ---- following a swipe ----
  // A swipe up opens the map as it goes (dragT is its progress); a swipe down on an
  // open map takes it back. Letting go finishes the move one way or the other.
  function grab() {                       // a swipe starts on an open (or closing) map
    if (phase !== "open" && phase !== "closing") return false;
    anim.stop();
    selRow = zoomRow = currentRow;
    selIdx = zoomIdx = repIndex(currentRow);
    snapFollow(t);                        // hold exactly where it is
    phase = "drag";
    return true;
  }
  // The map eases towards where the fingers are rather than jumping to it, so a fast
  // swipe is still seen: it can move at most this fast (t per second); lower is slower.
  property real follow: 0
  property bool easeFollow: false
  function snapFollow(v) { easeFollow = false; follow = v; easeFollow = true; }
  onDragTChanged: follow = dragT
  Component.onCompleted: { snapFollow(0); follow = dragT; }   // eases up to wherever the fingers already are
  Behavior on follow {
    enabled: ov.easeFollow
    SmoothedAnimation { velocity: 4.2; reversingMode: SmoothedAnimation.Sync }
  }
  onFollowChanged: if (phase === "drag") t = Math.max(0, Math.min(1, follow))
  // The fingers are up. open: where the move was going (true = the map).
  function release(open) {
    driven = false;
    if (phase === "drag") {
      anim.from = t;
      if (open) { phase = "open"; anim.to = 1; }
      else { phase = "closing"; anim.to = 0; }
      anim.restart();
    } else if (phase === "waiting") {
      // Not built yet (first moments of the swipe): go on as a normal open or give up.
      if (open) { if (ready) start(Math.max(0, dragT)); } else finished();
    }
  }
  function closeTo(row, idx) {
    if (phase === "closing") return;
    phase = "closing";
    zoomRow = row; zoomIdx = idx;
    anim.from = t; anim.to = 0; anim.restart();
  }
  function choose(row, idx) {
    if (phase !== "open") return;
    const desk = desksOf(row)[idx];
    if (!desk) return;
    const same = row === currentRow && desk.rep;
    if (!same) chosen(row, desk.id, desk.rep);
    closeTo(row, idx);
  }
  // Put your desktop back. Before the picture of it has arrived there is nothing to
  // zoom, so it just ends.
  function dismiss() {
    if (phase === "open") {
      selRow = currentRow; selIdx = repIndex(currentRow);
      closeTo(selRow, selIdx);
    } else if (phase === "waiting") finished();
  }

  // Begin as soon as there is something to show and the picture of your desktop is in.
  readonly property bool ready: dataReady && (snap.hasContent || fallback.running === false)
  onReadyChanged: if (ready) {
    if (driven) {                          // the swipe is still going: join it where it is
      selRow = zoomRow = currentRow;
      selIdx = zoomIdx = repIndex(currentRow);
      phase = "drag";
      t = Math.max(0, Math.min(1, follow));
    } else start(Math.max(0, dragT));
  }
  Timer { id: fallback; interval: 350; running: true }   // do not wait forever for the picture

  NumberAnimation { id: anim; target: ov; property: "t"; duration: 300; easing.type: Easing.OutQuart
                    onFinished: if (ov.phase === "closing") ov.finished() }

  focus: true
  // The search field owns the keyboard (see below), so it behaves as a normal text
  // box; these are the keys it hands back to the map.
  function fieldKey(event, field) {
    const k = event.key;
    if (k === Qt.Key_Escape) { event.accepted = true; if (field.text !== "") field.clear(); else dismiss(); }
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) { event.accepted = true; choose(selRow, selIdx); }
    else if (k === Qt.Key_Up) { event.accepted = true; move(-1, 0); }
    else if (k === Qt.Key_Down) { event.accepted = true; move(1, 0); }
    // Sideways walks the row until there is text to edit; then it is the caret's.
    else if ((k === Qt.Key_Left || k === Qt.Key_Right) && field.text === "") {
      event.accepted = true; move(0, k === Qt.Key_Left ? -1 : 1);
    }
  }

  // Scroll: up/down moves between rows, sideways (or shift) along the row.
  property real lastWheel: 0
  WheelHandler {
    onWheel: event => {
      const now = Date.now();
      if (now - ov.lastWheel < 140) return;
      const dx = event.angleDelta.x, dy = event.angleDelta.y;
      const horiz = Math.abs(dx) > Math.abs(dy) || (event.modifiers & Qt.ShiftModifier);
      const v = horiz ? (dx || dy) : dy;
      if (!v) return;
      ov.lastWheel = now;
      const s = v > 0 ? -1 : 1;
      if (horiz) ov.move(0, s); else ov.move(s, 0);
    }
  }

  // Plain background.
  Item {
    anchors.fill: parent
    opacity: ov.t
    Rectangle { anchors.fill: parent; color: ov.cBg }
    MouseArea { anchors.fill: parent; enabled: ov.phase === "open"; onClicked: ov.dismiss() }
  }

  // Row labels: a coloured bar, the row number, and what is in it.
  Repeater {
    model: ov.rows
    delegate: Item {
      id: lab
      required property var modelData
      required property int index
      readonly property bool isSel: ov.selRow === index
      readonly property bool isCur: ov.currentRow === index
      readonly property int nWs: { let n = 0; for (const d of modelData.desks) if (d.windows.length) n++; return n; }
      readonly property int nWin: { let n = 0; for (const d of modelData.desks) n += d.windows.length; return n; }
      z: 3
      x: ov.ox + 22 * ov.u - 10 * ov.u * (1 - ov.chrome)
      y: ov.tileY(index) + ov.tileH / 2 - 18 * ov.u
      opacity: ov.chrome
      Row {
        spacing: 6 * ov.u
        Rectangle {
          width: 3 * ov.u; height: 16 * ov.u; radius: 2 * ov.u
          color: lab.isSel ? ov.cAccent : lab.isCur ? ov.cGreen : ov.cRing
        }
        Text {
          text: String(lab.index + 1)
          color: lab.isSel ? ov.cFg : lab.isCur ? ov.cGreen : ov.cMute
          font.family: "JetBrains Mono"; font.weight: Font.Medium
          font.pixelSize: Math.round(18 * ov.u)
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      Text {
        y: 20 * ov.u
        x: 9 * ov.u
        lineHeight: 1.15
        text: lab.nWs + " ws\n" + lab.nWin + " win"
        color: ov.cMute
        font.family: "JetBrains Mono"
        font.pixelSize: Math.round(10.5 * ov.u)
      }
    }
  }

  // The map. At t = 0 it is scaled so the zoom-target desktop fills the screen.
  Item {
    id: world
    transformOrigin: Item.TopLeft
    scale: 1 + (ov.zoomS - 1) * (1 - ov.t)
    x: -ov.tileX(ov.zoomRow, ov.zoomIdx) * ov.zoomS * (1 - ov.t)
    y: -ov.tileY(ov.zoomRow) * ov.zoomS * (1 - ov.t)
    width: ov.width; height: ov.height

    Repeater {
      id: rowRepeater
      model: ov.rows

      delegate: Item {
        id: rowItem
        required property var modelData
        required property int index
        readonly property int focusIdx: ov.selRow === index ? ov.selIdx : ov.repIndex(index)
        readonly property int count: modelData.desks.length
        property real off: Math.max(0, Math.min(Math.max(0, count * ov.pitchX - 14 * ov.u - ov.visW),
                                                       focusIdx * ov.pitchX - (ov.visW - ov.tileW) / 2))
        Behavior on off { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        Repeater {
          model: rowItem.modelData.desks
          delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property bool isSel: ov.phase !== "waiting" && ov.selRow === rowItem.index && ov.selIdx === index
            readonly property bool isCur: ov.currentRow === rowItem.index && modelData.rep
            readonly property string q: ov.query.trim().toLowerCase()
            readonly property bool hit: q !== "" && ov.deskMatches(modelData, q).length > 0
            readonly property real px: ov.ox + ov.x0 + index * ov.pitchX - rowItem.off
            // Only desktops that are on screen get built: each one holds window pictures.
            readonly property bool near: px > -ov.pitchX * 1.5 && px < ov.width + ov.pitchX * 0.5
            x: px
            y: ov.tileY(rowItem.index)
            width: ov.tileW
            height: ov.tileH
            visible: near || (ov.zoomRow === rowItem.index && ov.zoomIdx === index)
            z: ov.zoomRow === rowItem.index && ov.zoomIdx === index ? 5 : 0

            // Ring: selected blue, your own desktop green, else a faint outline. Drawn
            // only while the map is up, so the zoomed desktop has no frame.
            Rectangle {
              anchors.fill: parent
              anchors.margins: -2 * ov.u
              radius: ov.radius * ov.chrome + 2 * ov.u
              color: "transparent"
              visible: tile.isSel
              opacity: ov.chrome
              border.width: 2 * ov.u
              border.color: ov.cAccent
            }
            Rectangle {
              anchors.fill: parent
              anchors.margins: -1 * ov.u
              radius: ov.radius * ov.chrome + 1 * ov.u
              color: "transparent"
              opacity: ov.chrome
              border.width: 1 * ov.u
              border.color: tile.isCur && !tile.isSel ? Qt.rgba(0.537, 0.792, 0.47, 0.6) : ov.cRing
              visible: !tile.isSel
            }

            Item {
              id: clip
              anchors.fill: parent
              // Square when it fills the screen, rounded as a miniature.
              Rectangle { anchors.fill: parent; color: ov.cTile }

              Loader {
                anchors.fill: parent
                active: tile.visible
                sourceComponent: tile.isCur && snap.hasContent ? snapView : deskView
              }
              Component {
                id: deskView
                Item {
                  Desk {
                    spec: tile.modelData
                    screenW: ov.screenW; screenH: ov.screenH
                    wallpaper: ov.wallpaper
                    captureFor: ov.captureFor
                    query: tile.q
                    scale: ov.shrink
                  }
                }
              }
              Component {
                id: snapView
                Item {
                  ShaderEffectSource {
                    sourceItem: snap
                    width: ov.screenW; height: ov.screenH
                    scale: ov.shrink
                    transformOrigin: Item.TopLeft
                    live: false
                    hideSource: false
                  }
                }
              }

              Rectangle {   // dims everything but the selection (and, searching, non-matches)
                anchors.fill: parent
                color: ov.cShade
                opacity: ov.chrome * (ov.query.trim() !== "" ? (tile.hit ? (tile.isSel ? 0 : 0.12) : 0.72)
                                                              : (tile.isSel ? 0 : 0.2))
              }
            }

            // Rounded corners: four background-coloured corner pieces over the tile.
            // Plain vector shapes (no offscreen layer), so they stay sharp however far
            // the map is zoomed and cost nothing while it moves.
            Repeater {
              model: [{ x: 0, y: 0, rot: 0 }, { x: 1, y: 0, rot: 90 }, { x: 1, y: 1, rot: 180 }, { x: 0, y: 1, rot: 270 }]
              delegate: Shape {
                required property var modelData
                readonly property real rad: ov.radius * ov.chrome
                visible: rad > 0.5
                width: rad; height: rad
                x: modelData.x ? tile.width - rad : 0
                y: modelData.y ? tile.height - rad : 0
                rotation: modelData.rot
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: ov.cBg
                  strokeWidth: -1
                  startX: 0; startY: 0
                  PathLine { x: rad; y: 0 }
                  PathArc { x: 0; y: rad; radiusX: rad; radiusY: rad; direction: PathArc.Counterclockwise }
                  PathLine { x: 0; y: 0 }
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: ov.phase === "open"
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: { ov.selRow = rowItem.index; ov.selIdx = tile.index; }
              onClicked: ov.choose(rowItem.index, tile.index)
            }

            // Caption: a dot on your own desktop, the workspace number, the apps in it.
            Row {
              y: ov.tileH + 3 * ov.u
              spacing: 6 * ov.u
              opacity: ov.chrome
              Text {
                visible: tile.isCur
                text: "●"; color: ov.cGreen
                font.family: "JetBrains Mono"; font.pixelSize: Math.round(10.5 * ov.u)
              }
              Text {
                text: String(tile.modelData.col)
                color: tile.isSel ? ov.cAccent : "#7f848e"
                font.family: "JetBrains Mono"; font.pixelSize: Math.round(10.5 * ov.u)
              }
              Text {
                readonly property var names: {
                  const seen = [];
                  for (const w of tile.modelData.windows) if (w.name && seen.indexOf(w.name) < 0) seen.push(w.name);
                  return seen;
                }
                width: ov.tileW - x
                elide: Text.ElideRight
                text: names.length ? names.join(" · ") : "empty"
                color: tile.isSel ? ov.cFg : names.length ? ov.cMute : ov.cDim
                font.family: "JetBrains Mono"; font.pixelSize: Math.round(10.5 * ov.u)
              }
            }
          }
        }
      }
    }
  }

  // Rows that run past the stage slide under these, which are the background colour.
  Rectangle { z: 2; x: 0; width: ov.ox + ov.x0 - 34 * ov.u; height: parent.height; color: ov.cBg; opacity: ov.chrome }
  Rectangle {
    z: 2
    x: ov.ox + ov.x0 - 34 * ov.u; width: 32 * ov.u; height: parent.height
    opacity: ov.chrome
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: ov.cBg }
      GradientStop { position: 1; color: Qt.rgba(0.157, 0.173, 0.204, 0) }
    }
  }
  Rectangle {
    z: 2
    x: ov.ox + ov.stageW - 44 * ov.u; width: 44 * ov.u; height: parent.height
    opacity: ov.chrome
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.rgba(0.157, 0.173, 0.204, 0) }
      GradientStop { position: 1; color: ov.cBg }
    }
  }
  Rectangle { z: 2; x: ov.ox + ov.stageW; width: ov.width - x; height: parent.height; color: ov.cBg; opacity: ov.chrome }

  // Search pill.
  Rectangle {
    id: pill
    z: 3
    anchors.horizontalCenter: parent.horizontalCenter
    y: 28 * ov.u - 8 * ov.u * (1 - ov.chrome)
    width: 440 * ov.u; height: 30 * ov.u; radius: height / 2
    color: ov.cTile
    opacity: ov.chrome
    border.width: Math.max(1, ov.u)
    border.color: ov.query === "" ? ov.cRing : ov.hitWindows ? "#88e5c07b" : "#88ef596f"

    Row {
      anchors.verticalCenter: parent.verticalCenter
      x: 12 * ov.u
      spacing: 10 * ov.u
      Item {   // magnifier, drawn: a ring and a handle
        width: 16 * ov.u; height: 16 * ov.u
        anchors.verticalCenter: parent.verticalCenter
        readonly property color ink: ov.query === "" ? ov.cMute : ov.cYellow
        Rectangle {
          x: 1.5 * ov.u; y: 1.5 * ov.u
          width: 10 * ov.u; height: 10 * ov.u; radius: width / 2
          color: "transparent"; border.width: 1.6 * ov.u; border.color: parent.ink
        }
        Rectangle {
          x: 9.6 * ov.u; y: 12.2 * ov.u
          width: 6.4 * ov.u; height: 1.8 * ov.u; radius: height / 2
          color: parent.ink
          transformOrigin: Item.Left
          rotation: 45
        }
      }
    }
    TextInput {
      id: field
      anchors.left: parent.left; anchors.leftMargin: 38 * ov.u
      anchors.right: countText.left; anchors.rightMargin: 10 * ov.u
      anchors.verticalCenter: parent.verticalCenter
      focus: true
      clip: true
      maximumLength: 64
      color: ov.cFg
      selectionColor: ov.cAccent
      selectedTextColor: ov.cBg
      selectByMouse: true
      font.family: "JetBrains Mono"; font.pixelSize: Math.round(13 * ov.u)
      onTextChanged: ov.query = text
      Keys.onPressed: event => ov.fieldKey(event, field)
      // A thin line that blinks, like a terminal's bar cursor.
      cursorDelegate: Rectangle { width: Math.max(1.5, 1.5 * ov.u); color: ov.cAccent }
      Text {
        visible: field.text === ""
        text: "type to find a window"; color: ov.cMute
        font: field.font
      }
    }
    Text {
      id: countText
      anchors.right: parent.right; anchors.rightMargin: 12 * ov.u
      anchors.verticalCenter: parent.verticalCenter
      text: ov.query === "" ? ov.totalWindows + " windows"
            : ov.hitWindows ? ov.hitWindows + " in " + ov.hits.length + " ws" : "no match"
      color: ov.query !== "" && !ov.hitWindows ? ov.cRed : ov.cMute
      font.family: "JetBrains Mono"; font.pixelSize: Math.round(11 * ov.u)
    }
  }

  // Key hints.
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height - 40 * ov.u
    spacing: 16 * ov.u
    opacity: ov.chrome
    Repeater {
      model: [
        { k: "←↑↓→", l: "move" }, { k: "⏎", l: "go" }, { k: "type", l: "search" },
        { k: "esc", l: ov.query !== "" ? "clear" : "back" }, { k: "scroll", l: "rows" },
      ]
      delegate: Text {
        required property var modelData
        textFormat: Text.StyledText
        text: "<font color='#e5c07b'>" + modelData.k + "</font> " + modelData.l
        color: ov.cMute
        font.family: "JetBrains Mono"; font.pixelSize: Math.round(11 * ov.u)
      }
    }
  }

  // The picture of your real screen, taken before the overlay appeared. Never shown
  // directly: your own desktop's tile is drawn from it.
  ScreencopyView {
    id: snap
    width: ov.screenW; height: ov.screenH
    x: -ov.screenW - 100        // off screen but live, so the tile can sample it
    captureSource: ov.screenSource
    live: false
    paintCursor: false
    Component.onCompleted: if (captureSource) captureFrame()
  }
}

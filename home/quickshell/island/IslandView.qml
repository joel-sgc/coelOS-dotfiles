import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."
import "../desktop/data"
import "Parts.js" as P

// One screen's island (IslandEngine.qml holds the state; every bar mirrors it).
//
// A single transparent Overlay surface spanning the bar's width draws the island
// both docked (inside the bar, right-aligned to the clock's left edge) and
// floating (centred, 6 px under the bar), so "lift" and "land" are one
// continuous morph of x/y/width rather than a hand-off between two windows.
// Only the island itself takes input (mask). The surface is just bar-tall
// while docked and grows only while something floats.
PanelWindow {
  id: view

  property var engine
  property var barWindow: null
  property int barHeight: 36
  // x (in bar coordinates) of the island's right edge when docked.
  property real dockRight: 0
  // A fullscreen window on this monitor hides everything but interrupts.
  property bool fullscreen: false

  // ---- hand-off with the desktop (Desktop Board "the travel") ----
  // While this monitor's workspace is empty, an activity whose card the desktop
  // has open (DeskState.openRects) leaves the pill: its chip flies into the card. When
  // a window opens it flies back. Interrupts always stay on the pill.
  property bool emptyWs: false
  property bool monitorFocused: false
  readonly property var deskOpen: (screen && DeskState.openRects[screen.name]) || ({})
  readonly property var handedCards: emptyWs ? Object.keys(deskOpen) : []
  Binding { when: view.monitorFocused && !!view.engine; target: view.engine; property: "handedCards"; value: view.handedCards }
  property var flyingBack: []   // chip ids on their way back (kept off the pill until they land)
  readonly property var hiddenChips: !engine ? [] : engine.chips
    .filter(c => c.deskCard && handedCards.indexOf(c.deskCard) >= 0).map(c => c.id).concat(flyingBack)

  readonly property var collapsedSpec: ({ tier: "collapsed", groups: [], rowKey: "rest", dropKey: "none" })
  readonly property var target: (!engine || (fullscreen && engine.spec.tier !== "interrupt")) ? collapsedSpec : engine.specWithout(hiddenChips)

  property var prevHanded: []
  onHandedCardsChanged: {
    const now = handedCards, before = prevHanded;
    prevHanded = now;
    if (!engine) return;
    const chips = engine.chips.filter(c => c.deskCard);
    const toDesk = chips.filter(c => now.indexOf(c.deskCard) >= 0 && before.indexOf(c.deskCard) < 0);
    const toPill = chips.filter(c => before.indexOf(c.deskCard) >= 0 && now.indexOf(c.deskCard) < 0);
    if (!candy || (toDesk.length === 0 && toPill.length === 0)) { flyingBack = []; return; }
    // Where the chips sit on the dock right now (the shape hasn't moved yet):
    // spread across the island, left to right, as the pill draws them.
    const onPill = engine.chips.filter(c => !c.deskCard || before.indexOf(c.deskCard) < 0).slice(0, 2);
    const dockAt = (c, i, n) => ({ x: shape.x + 11 + (shape.width - 22) * (i + 0.5) / n - 20, y: 5 });
    const ghosts = [];
    toDesk.forEach((c, k) => {
      const i = Math.max(0, onPill.findIndex(x => x.id === c.id)), r = deskOpen[c.deskCard];
      if (!r) return;
      const from = dockAt(c, i, Math.max(1, onPill.length));
      ghosts.push({ key: c.id + "-in", chipId: c.id, cardId: c.deskCard, groups: c.parts, toDesk: true,
                    x0: from.x, y0: from.y, x1: r.x + 22, y1: r.y + 12, s0: 1, s1: 1.6, delay: k * 40 });
    });
    toPill.forEach((c, k) => {
      const r = deskOpen[c.deskCard];
      if (!r) return;
      ghosts.push({ key: c.id + "-out", chipId: c.id, cardId: c.deskCard, groups: c.parts, toDesk: false,
                    x0: r.x + 22, y0: r.y + 12, x1: dockRight - 70 * (toPill.length - k), y1: 5, s0: 1.6, s1: 1, delay: k * 40 });
    });
    flyingBack = toPill.map(c => c.id);
    flights = ghosts;
    landedCount = 0;
  }
  property var flights: []
  property int landedCount: 0
  function landed(g) {
    if (g.toDesk) DeskState.flash(g.cardId);
    else flyingBack = flyingBack.filter(id => id !== g.chipId);
    landedCount += 1;
    if (landedCount >= flights.length) { flights = []; flyingBack = []; }
  }
  // What is drawn right now; trails `target` by the content fade.
  property var shown: collapsedSpec

  readonly property bool floating: target.tier === "glance" || target.tier === "interrupt" || target.tier === "card"
  readonly property bool candy: !Globals.eyeCandyOff

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; left: true; right: true }
  // Fixed while mapped: resizing a mapped layer surface flashed a tall frame.
  // Full height so chips can fly to cards anywhere on the desktop.
  implicitHeight: screen ? screen.height : 720
  visible: target.tier !== "collapsed" || shape.opacity > 0.001 || flights.length > 0
  mask: Region { item: shape; Region { item: dockBridge } }

  // While a hover-opened card floats, the spot it lifted off from still counts
  // as the island: the pointer is usually still sitting there, and without this
  // the lift itself read as "pointer left" and closed the card again.
  readonly property bool bridging: target.tier === "card" && !!engine && !engine.cardPinned
  Item {
    id: dockBridge
    width: view.bridging ? measure.implicitWidth + 22 : 0
    height: view.bridging ? 26 : 0
    x: view.dockRight - width
    y: 5
    HoverHandler {
      id: bridgeHover
      cursorShape: Qt.PointingHandCursor
    }
    TapHandler { onTapped: view.engine.activate(view.screen) }
  }
  // One hover signal for the engine: island or bridge.
  readonly property bool hovered: shapeHover.hovered || (bridging && bridgeHover.hovered)
  onHoveredChanged: hovered ? engine.hoverEnter() : engine.hoverLeave()

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "coel-island"
  WlrLayershell.keyboardFocus: (engine && engine.cardPinned && engine.cardScreen === view.screen)
    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  HyprlandFocusGrab {
    windows: view.barWindow ? [view, view.barWindow] : [view]
    active: !!view.engine && view.engine.cardPinned && view.engine.cardScreen === view.screen
    onCleared: view.engine.closeCard()
  }

  // ---- content swap: outgoing fades (exit), shown flips, incoming fades (enter) ----
  property bool fadeRow: false
  property bool fadeDrop: false
  onTargetChanged: {
    const rowChange = target.rowKey !== shown.rowKey;
    const dropChange = target.dropKey !== shown.dropKey;
    if ((!rowChange && !dropChange) || !candy) { swap.stop(); rowLayer.opacity = 1; dropLayer.opacity = 1; shown = target; return; }
    fadeRow = rowChange;
    fadeDrop = dropChange;
    swap.restart();
  }
  SequentialAnimation {
    id: swap
    ParallelAnimation {
      NumberAnimation { target: rowLayer; property: "opacity"; to: view.fadeRow ? 0 : 1; duration: 90; easing.type: Easing.BezierSpline; easing.bezierCurve: P.exit }
      NumberAnimation { target: dropLayer; property: "opacity"; to: view.fadeDrop ? 0 : 1; duration: 80; easing.type: Easing.BezierSpline; easing.bezierCurve: P.exit }
    }
    ScriptAction { script: view.shown = view.target }
    ParallelAnimation {
      NumberAnimation { target: rowLayer; property: "opacity"; to: 1; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: P.enter }
      SequentialAnimation {
        PauseAnimation { duration: view.fadeDrop ? 40 : 0 }
        NumberAnimation { target: dropLayer; property: "opacity"; to: 1; duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: P.enter }
      }
    }
  }

  // ---- geometry ----
  // 0 = docked, 1 = floating. Position is interpolated from this, so x/y/width
  // land together and the dock end stays glued to the clock while width animates.
  property real lift: floating ? 1 : 0
  Behavior on lift {
    enabled: view.candy
    NumberAnimation { duration: view.floating ? 260 : 240; easing.type: Easing.BezierSpline; easing.bezierCurve: P.morph }
  }

  // Hidden copy of the target row, so the shape starts morphing to its new
  // width while the old content is still fading out.
  IslandRow { id: measure; visible: false; groups: view.target.groups }

  readonly property bool hasDrop: !!shown.drop && !!dropLoader.item
  readonly property real targetW: target.tier === "collapsed" ? 0
    : Math.max(measure.implicitWidth + 22, hasDrop ? dropLoader.item.implicitWidth + 28 : 0)
  readonly property real targetH: 26 + (hasDrop ? dropLoader.item.implicitHeight + 4 + 14 : 0)

  RectangularShadow {
    anchors.fill: shape
    radius: shape.radius
    offset.y: 12
    blur: 26
    spread: -8
    color: Qt.rgba(0, 0, 0, 0.55)
    opacity: view.lift * shape.opacity
    visible: opacity > 0.01
  }

  Rectangle {
    id: shape
    width: view.targetW
    height: view.targetH
    Behavior on width {
      enabled: view.candy
      NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: P.morph }
    }
    Behavior on height {
      enabled: view.candy
      NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: P.morph }
    }
    x: (view.dockRight - width) * (1 - view.lift) + ((view.width - width) / 2) * view.lift
    y: 5 * (1 - view.lift) + (view.barHeight + 6) * view.lift

    opacity: view.target.tier === "collapsed" ? 0 : 1
    Behavior on opacity {
      enabled: view.candy
      NumberAnimation { duration: 120; easing.type: Easing.BezierSpline; easing.bezierCurve: view.target.tier === "collapsed" ? P.exit : P.enter }
    }

    color: P.C.bg
    radius: Globals.eyeCandyOff ? 0 : (view.hasDrop ? 18 : 13)
    border.width: 1
    border.color: view.shown.tier === "interrupt" ? view.shown.accent : P.C.sf
    clip: true

    HoverHandler { id: shapeHover }

    FocusScope {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: view.engine.cancel()

      Item {
        id: rowLayer
        width: parent.width
        height: 26
        // Only the row line is a button; clicks inside a card/drop stay with it.
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: view.engine.activate(view.screen) }
        IslandRow {
          anchors.centerIn: parent
          groups: view.shown.groups
        }

        // 2 px "working" sweep under the capsule (assistant).
        Rectangle {
          visible: !!view.shown.sweep
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          anchors.bottomMargin: 2
          height: 2
          radius: 1
          color: P.C.sf
          clip: true
          Rectangle {
            id: sweepBar
            width: parent.width * 0.34
            height: 2
            radius: 1
            color: P.C.pu
            NumberAnimation on x {
              running: !!view.shown.sweep && view.candy
              loops: Animation.Infinite
              from: -sweepBar.width
              to: sweepBar.parent.width
              duration: 1100
              easing.type: Easing.InOutSine
            }
          }
        }
      }

      Item {
        id: dropLayer
        y: 30
        x: 14
        width: parent.width - 28
        height: dropLoader.item ? dropLoader.item.implicitHeight : 0
        Loader {
          id: dropLoader
          anchors.horizontalCenter: parent.horizontalCenter
          sourceComponent: !view.shown.drop ? null
            : view.shown.drop === "activities" ? activitiesCard : view.shown.drop
          onLoaded: {
            if ("engine" in item) item.engine = view.engine;
            if ("screen" in item) item.screen = view.screen;
            if ("entry" in item) item.entry = Qt.binding(() => view.shown.entry);
            if ("source" in item) item.source = view.shown.chip ? view.shown.chip.source
              : (view.shown.entry ? view.shown.entry.source : null);
          }
        }
      }
    }
  }

  Component {
    id: activitiesCard
    ActivitiesCard {}
  }

  // ---- the flying chips (one short flight each, 280 ms on the morph curve) ----
  Repeater {
    model: view.flights
    delegate: Item {
      id: gh
      required property var modelData
      property real t: 0
      x: modelData.x0 + (modelData.x1 - modelData.x0) * t
      y: modelData.y0 + (modelData.y1 - modelData.y0) * t
      scale: modelData.s0 + (modelData.s1 - modelData.s0) * t
      transformOrigin: Item.TopLeft
      // Into a card: fades as it lands. Back to the pill: fades in as it leaves.
      opacity: modelData.toDesk ? (t < 0.75 ? 1 : (1 - t) / 0.25) : Math.min(1, t / 0.2)
      width: ghostRow.implicitWidth + 22
      height: 26
      Rectangle {
        anchors.fill: parent
        radius: Globals.eyeCandyOff ? 0 : 13
        color: P.C.bg
        border.width: 1
        border.color: P.C.sf
      }
      IslandRow { id: ghostRow; anchors.centerIn: parent; groups: gh.modelData.groups }
      SequentialAnimation {
        running: true
        PauseAnimation { duration: gh.modelData.delay }
        NumberAnimation { target: gh; property: "t"; from: 0; to: 1; duration: 280; easing.type: Easing.BezierSpline; easing.bezierCurve: P.morph }
        ScriptAction { script: view.landed(gh.modelData) }
      }
    }
  }
}

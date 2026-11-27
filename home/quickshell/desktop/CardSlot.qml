import QtQuick
import ".."
import "data"
import "Layout.js" as L

// One card's place on the desktop. `p` is its placement from Layout.place()
// ({x, y, w, slot, spec}) or null when the current layout doesn't show it.
// Position and width glide between hero, rail and shelf (260 ms, morph); a size
// change swaps the content with a short cross-fade (out 90 ms, in 140 ms).
// A card appearing from nowhere fades in where it lands instead of flying in.
FocusScope {
  id: slot
  property string cardId: ""
  property var p: null
  property Component card: null
  // The card's settled height, for the layout (rail stacking, shelf baseline).
  readonly property real cardHeight: loader.item ? loader.item.implicitHeight : 0

  readonly property bool candy: !Globals.eyeCandyOff
  readonly property var morph: [0.2, 0, 0, 1, 1, 1]

  // What the card is drawing; trails p.spec through the cross-fade.
  property string shownSize: p ? p.spec.size : "M"
  property string shownFlavor: p ? p.spec.flavor : ""
  property bool placedOnce: false
  property bool glide: false

  onPChanged: {
    if (!p) return;
    if (!placedOnce) {   // first appearance: jump into place, then fade in
      glide = false;
      x = p.x; y = p.y; width = p.w;
      shownSize = p.spec.size; shownFlavor = p.spec.flavor;
      placedOnce = true;
      Qt.callLater(() => slot.glide = true);
      return;
    }
    x = p.x; y = p.y; width = p.w;
    if (p.spec.size !== shownSize || p.spec.flavor !== shownFlavor) {
      if (!candy) { shownSize = p.spec.size; shownFlavor = p.spec.flavor; }
      else swap.restart();
    }
  }
  SequentialAnimation {
    id: swap
    NumberAnimation { target: loader; property: "opacity"; to: 0; duration: 90; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 1, 1, 1, 1] }
    ScriptAction { script: { slot.shownSize = slot.p ? slot.p.spec.size : slot.shownSize; slot.shownFlavor = slot.p ? slot.p.spec.flavor : slot.shownFlavor; } }
    PauseAnimation { duration: 20 }
    NumberAnimation { target: loader; property: "opacity"; to: 1; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: [0, 0, 0.2, 1, 1, 1] }
  }

  Behavior on x { enabled: slot.glide && slot.candy; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: slot.morph } }
  Behavior on y { enabled: slot.glide && slot.candy; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: slot.morph } }
  Behavior on width { enabled: slot.glide && slot.candy; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: slot.morph } }
  height: cardHeight
  Behavior on height { enabled: slot.glide && slot.candy; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: slot.morph } }

  // The greeting holds cards back, then lets them in: hero/rail first (staggered by
  // `greetDelay`), the shelf last.
  property int greetDelay: 0
  readonly property bool greetHidden: DeskState.greetPhase === 1
    || (DeskState.greetPhase === 2 && !!p && p.slot === "shelf")
  opacity: p && !greetHidden ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity {
    enabled: slot.candy
    SequentialAnimation {
      PauseAnimation { duration: DeskState.greetPhase === 2 ? slot.greetDelay : 0 }
      NumberAnimation { duration: DeskState.greetPhase >= 2 ? 240 : 160; easing.type: Easing.BezierSpline; easing.bezierCurve: [0, 0, 0.2, 1, 1, 1] }
    }
  }
  transform: Translate {
    y: slot.greetHidden ? 6 : 0
    Behavior on y { enabled: slot.candy; NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: [0, 0, 0.2, 1, 1, 1] } }
  }

  // The size it should take when you open it from the shelf.
  readonly property string railSize: L.SMALL.indexOf(cardId) >= 0 ? "S" : "C"
  function toggleMin() {
    if (!p) return;
    if (p.spec.size === "M") DeskState.open(cardId, railSize);
    else DeskState.minimize(cardId);
  }
  function togglePin() {
    if (p) DeskState.togglePin(cardId, p.slot, p.spec.size, railSize);
  }

  // One flash (DeskState.flash): a chip landed here, or a glance about this card
  // was skipped because the card is on screen.
  readonly property int flashCount: DeskState.flashes[cardId] || 0
  onFlashCountChanged: if (candy && p) flashAnim.restart()
  SequentialAnimation {
    id: flashAnim
    NumberAnimation { target: loader; property: "opacity"; to: 0.6; duration: 110; easing.type: Easing.OutQuad }
    NumberAnimation { target: loader; property: "opacity"; to: 1; duration: 130; easing.type: Easing.InQuad }
  }

  Loader {
    id: loader
    width: slot.width
    sourceComponent: slot.card
    onLoaded: {
      item.size = Qt.binding(() => slot.shownSize);
      item.flavor = Qt.binding(() => slot.shownFlavor);
      item.pinned = Qt.binding(() => !!DeskState.pin[slot.cardId]);   // by you (p); mode pins aren't badged
      item.focused = Qt.binding(() => slot.activeFocus && DeskState.focusId === slot.cardId);
      item.width = Qt.binding(() => slot.width);
      item.minToggled.connect(slot.toggleMin);
    }
  }

  // Focus follows the pointer; keys go to the focused card.
  HoverHandler {
    onHoveredChanged: if (hovered) { DeskState.focusId = slot.cardId; slot.forceActiveFocus(); }
  }
  TapHandler {
    onPressedChanged: if (pressed) { DeskState.focusId = slot.cardId; slot.forceActiveFocus(); }
  }
  Keys.onPressed: (e) => {
    if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
    if (loader.item && loader.item.handleKey(e)) { e.accepted = true; return; }
    if (e.text === "m") { slot.toggleMin(); e.accepted = true; }
    else if (e.text === "p") { slot.togglePin(); e.accepted = true; }
    else e.accepted = false;   // let the desktop see it (M, esc)
  }
}

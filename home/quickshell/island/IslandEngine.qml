import QtQuick
import Quickshell
import "Parts.js" as P

// The live-activity island's brain: one instance (Panel.qml's panelScope),
// mirrored by an IslandView on every bar. Rules from the Pill Board:
//
//   ambient   chips from every source, two most urgent + "+n", docked left of the clock
//   glance    one line floating under the bar for a few seconds; FIFO queue, a source
//             replaces its own pending glance; held during DND, replayed after
//   interrupt floats with an accent ring until dismissed; stacks ("1/2"); beats everything
//   card      hover the dock 250 ms (or click to pin); with 2+ chips the activities list
//
// A source is any object with a `chips` list (see sources/). A chip is
//   { id, source, prio, parts: [[part...]...] (groups, Parts.js), label, value,
//     valueColor, card: Component|null, activate: function|null, sweep: bool }
// Lower prio = more urgent: recording 10, call 20, class 30, assistant 40,
// printer 50, pomodoro 60, music 70, casting 80, vpn 90, phone battery 100.
// A glance/interrupt is
//   { id, parts: [part...] (one per group), accent, ms, drop: Component|null,
//     source, activate: function|null, force: bool (show even during DND) }
Scope {
  id: engine

  property var sources: []
  // Do Not Disturb (the notification backend's). Interrupts still show,
  // silently; glances wait and play in order once it ends.
  property bool dnd: false

  readonly property var chips: {
    const out = [];
    for (const s of sources) if (s && s.chips) for (const c of s.chips) out.push(c);
    out.sort((a, b) => a.prio - b.prio);
    return out;
  }

  property var current: null
  property var queue: []
  property var held: []
  property var interrupts: []

  // "" closed, "auto" (one chip -> its card, 2+ -> activities), "activities", or a chip id.
  property string cardId: ""
  property bool cardPinned: false
  // Screen whose bar pinned the card: only that view grabs focus for it.
  property var cardScreen: null
  readonly property bool cardOpen: cardId !== "" && spec.tier === "card"

  // ---- glances ----
  function glance(g) {
    held = held.filter(q => q.id !== g.id);
    // `force`: a glance that must show even during DND (e.g. the mode change
    // that just turned DND on).
    if (dnd && !g.force) { held = held.concat([g]); return; }
    if (current && current.id === g.id) { current = g; armGlance(); return; }
    if (current) { queue = queue.filter(q => q.id !== g.id).concat([g]); return; }
    current = g;
    armGlance();
  }
  function dismissGlance() {
    if (queue.length) { current = queue[0]; queue = queue.slice(1); }
    else current = null;
    armGlance();
  }
  // A glance only counts down while it is actually on screen.
  function armGlance() {
    if (current && interrupts.length === 0 && cardId === "") {
      glanceTimer.interval = current.ms || 3000;
      glanceTimer.restart();
    } else glanceTimer.stop();
  }
  Timer { id: glanceTimer; onTriggered: engine.dismissGlance() }

  onDndChanged: if (!dnd && held.length) {
    const h = held;
    held = [];
    h.forEach(g => glance(g));
  }

  // ---- interrupts ----
  function interrupt(i) {
    const at = interrupts.findIndex(x => x.id === i.id);
    if (at >= 0) { const n = interrupts.slice(); n[at] = i; interrupts = n; }
    else { interrupts = interrupts.concat([i]); closeCard(); }
    armGlance();
  }
  function dismissInterrupt(id) {
    interrupts = id ? interrupts.filter(x => x.id !== id) : interrupts.slice(1);
    armGlance();
  }

  // Take back a glance or interrupt that no longer applies (resumed print, ...).
  function withdraw(id) {
    held = held.filter(q => q.id !== id);
    queue = queue.filter(q => q.id !== id);
    if (interrupts.some(x => x.id === id)) dismissInterrupt(id);
    if (current && current.id === id) dismissGlance();
  }

  // ---- card ----
  function openCard(id, pinned, screen) {
    hoverTimer.stop();
    leaveTimer.stop();
    cardId = id;
    cardPinned = !!pinned;
    cardScreen = pinned ? screen : null;
    armGlance();
  }
  function closeCard() {
    cardId = "";
    cardPinned = false;
    cardScreen = null;
    armGlance();
  }

  // Hover: 250 ms on the dock peeks the card; leaving for 450 ms closes an
  // unpinned one (long enough to follow it as it floats away from the dock).
  // When a hover-opened card closes, the island lands back in the dock, often
  // right under a pointer that never moved: that must not count as a new hover
  // (it reopened the card in a loop).
  property real hoverClosedAt: 0
  function hoverEnter() {
    leaveTimer.stop();
    if (Date.now() - hoverClosedAt < 400) return;
    if (spec.tier === "ambient" && cardId === "") hoverTimer.restart();
  }
  function hoverLeave() {
    hoverTimer.stop();
    if (cardId !== "" && !cardPinned) leaveTimer.restart();
  }
  Timer {
    id: hoverTimer
    interval: 250
    onTriggered: if (engine.spec.tier === "ambient" && engine.cardId === "") engine.openCard("auto", false, null)
  }
  Timer {
    id: leaveTimer
    interval: 450
    onTriggered: if (!engine.cardPinned) { engine.hoverClosedAt = Date.now(); engine.closeCard(); }
  }

  // What a click on the island does, per tier.
  function activate(screen) {
    const t = spec.tier;
    if (t === "ambient") {
      const only = chips.length === 1 ? chips[0] : null;
      if (only && !only.card && only.activate) only.activate();
      else openCard("auto", true, screen);
    } else if (t === "card") {
      if (cardPinned) closeCard();
      else { cardPinned = true; cardScreen = screen; leaveTimer.stop(); }
    } else if (t === "glance") {
      const g = current;
      if (g && g.activate) g.activate();
      else if (g && g.source && chips.some(c => c.source === g.source && c.card)) {
        const c = chips.find(c => c.source === g.source && c.card);
        dismissGlance();
        openCard(c.id, true, screen);
      } else dismissGlance();
    } else if (t === "interrupt") {
      const i = interrupts[0];
      if (i && i.activate) i.activate();
      else if (i && !i.drop) dismissInterrupt(i.id);
    }
  }
  // Esc: close the card, else drop the glance. Interrupts need an explicit choice.
  function cancel() {
    if (cardId !== "") closeCard();
    else if (spec.tier === "glance") dismissGlance();
  }

  // Close a card whose activity went away underneath it.
  onChipsChanged: if (cardId !== "" && spec.tier !== "card") closeCard()

  // ---- what to show ----
  // groups: row content; rowKey/dropKey change => content cross-fades.
  readonly property var spec: {
    const shown = chips.slice(0, 2), more = chips.length - shown.length;
    const ambGroups = [];
    shown.forEach((c, i) => {
      if (i > 0) ambGroups.push([P.space(4)]);
      for (const g of c.parts) ambGroups.push(g);
    });
    if (more > 0) ambGroups.push([P.muted("+" + more, 12)]);
    const ambKey = "amb:" + shown.map(c => c.id).join(",") + (more > 0 ? "+" : "");
    const sweep = shown.some(c => c.sweep);

    if (cardId !== "") {
      let id = cardId;
      if (id === "auto") id = chips.length >= 2 ? "activities" : (chips.length ? chips[0].id : "");
      let drop = null, chip = null;
      if (id === "activities" && chips.length >= 2) drop = "activities";
      else {
        chip = chips.find(c => c.id === id) || null;
        if (chip && chip.card) drop = chip.card;
      }
      if (drop) return { tier: "card", groups: ambGroups, sweep: sweep, rowKey: ambKey,
                         drop: drop, chip: chip, dropKey: "card:" + id };
    }
    if (interrupts.length) {
      const i = interrupts[0];
      const groups = P.spread(i.parts);
      if (interrupts.length > 1) groups.push([P.muted("1/" + interrupts.length)]);
      return { tier: "interrupt", accent: i.accent || P.C.err, groups: groups, rowKey: "int:" + i.id,
               drop: i.drop || null, entry: i, dropKey: i.drop ? "int:" + i.id : "none" };
    }
    if (current) {
      const groups = P.spread(current.parts);
      if (queue.length) groups.push([P.space(0), P.dot(P.C.fg, 4), P.dot(P.C.sf, 4)]);
      return { tier: "glance", accent: current.accent || P.C.sf, groups: groups, rowKey: "gl:" + current.id,
               drop: current.drop || null, entry: current, dropKey: current.drop ? "gl:" + current.id : "none" };
    }
    if (chips.length) return { tier: "ambient", groups: ambGroups, sweep: sweep, rowKey: ambKey, dropKey: "none" };
    return { tier: "collapsed", groups: [], rowKey: "rest", dropKey: "none" };
  }
}

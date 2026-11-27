.pragma library

// The desktop's layout engine, ported from example/Desktop Board.dc.html (`RECIPE`,
// `layout()`): one recipe per mode puts cards in three places, then your pins
// and minimizes are applied on top, so they always win.
//
//   hero   one card, top-left, 760 px (L)
//   rail   up to four cards, top-right, 360 px (C compact / S small)
//   shelf  minimized headers along the bottom (M)
//
// Card ids: next weather kanban pomo printer music phone server calendar.
// A recipe entry is [id, size, flavor]; flavor picks a variant (next up's class
// countdown, kanban filtered to the class's tag, ...).

const RECIPE = {
  morning: { hero: ["next", "L"], rail: [["weather", "C"], ["kanban", "C"], ["pomo", "C"]], shelf: ["server", "phone", "printer", "music", "calendar"] },
  class: { hero: ["next", "L", "class"], rail: [["kanban", "C", "class"]], shelf: ["weather", "pomo", "printer", "music", "server", "phone"] },
  deep_work: { hero: ["pomo", "L"], rail: [["kanban", "C"], ["next", "C"]], shelf: ["weather", "music", "printer", "server", "phone"] },
  printing: { hero: ["printer", "L"], rail: [["music", "S"], ["next", "C"], ["kanban", "C"], ["weather", "C"]], shelf: ["pomo", "server", "phone"] },
  music: { hero: ["music", "L"], rail: [["next", "C"], ["weather", "C"], ["kanban", "C"]], shelf: ["pomo", "printer", "server", "phone"] },
  evening: { hero: ["next", "L", "winddown"], rail: [["kanban", "C"], ["weather", "C"]], shelf: ["pomo", "music", "printer", "server", "phone"] },
  gaming: { hero: null, rail: [["phone", "S"], ["printer", "S"], ["music", "S"]], shelf: [] },
};

// The cards a mode's recipe puts on the desktop (hero, then rail): the mode's
// default pins (modes/Modes.qml pinnedCards), so they come back each time the
// mode begins even if you minimized them.
function recipeCards(mode) {
  const r = RECIPE[mode];
  if (!r) return [];
  return (r.hero ? [r.hero[0]] : []).concat(r.rail.map(e => e[0]));
}

// Live-activity cards that get a small size in the rail; the rest go compact.
var SMALL = ["printer", "music", "phone"];

// Every card the recipe leaves out goes to the end of the shelf (our deviation
// from the board, which shelved only some per mode), except in gaming, where the
// desktop is only seen alt-tabbed out of a game.
const ORDER = ["next", "weather", "kanban", "pomo", "printer", "music", "phone", "server", "calendar"];

// ctx: { mode, available: {id: true} (cards that exist / have something to show),
//        printerActive, musicActive, modePinned: [id] (settings.toml
//        [modes.<mode>] pinned), user: { min: {id: true}, pin: {id: {where, size}} } }
// returns { hero: spec|null, rail: [spec], shelf: [spec] }, spec = { id, size, flavor, pinned, mine }
function layout(ctx) {
  const r = RECIPE[ctx.mode] || RECIPE.morning;
  const user = ctx.user || { min: {}, pin: {} };
  const avail = ctx.available || {};
  const present = id => {
    if (!avail[id]) return false;
    if (id === "music") return !!ctx.musicActive;
    if (id === "printer" && ctx.mode === "gaming") return !!ctx.printerActive;
    return true;
  };

  let hero = r.hero && present(r.hero[0]) ? { id: r.hero[0], size: r.hero[1], flavor: r.hero[2] || "" } : null;
  let rail = r.rail.filter(e => present(e[0])).map(e => ({ id: e[0], size: e[1], flavor: e[2] || "" }));
  let shelf = r.shelf.filter(present).map(id => ({ id: id, size: "M", flavor: "" }));
  const all = () => [hero].concat(rail, shelf).filter(Boolean);

  // the mode's own pins (settings.toml): always on the desktop in this mode.
  // Where the recipe already shows one it stays put; otherwise it goes to the
  // top of the rail, ahead of the rail's 4-card limit. Your pins and minimizes
  // below still apply on top (DeskState un-minimizes these on entering the mode).
  const modePinned = (ctx.modePinned || []).filter(id => ORDER.indexOf(id) >= 0 && present(id));
  for (const id of modePinned.slice().reverse()) {
    if (hero && hero.id === id) { hero.modePinned = true; continue; }
    const inRail = rail.find(s => s.id === id);
    if (inRail) { inRail.modePinned = true; rail = [inRail].concat(rail.filter(s => s !== inRail)); continue; }
    shelf = shelf.filter(s => s.id !== id);
    rail.unshift({ id: id, size: SMALL.indexOf(id) >= 0 ? "S" : "C", flavor: "", modePinned: true });
  }

  // pins: a pinned card keeps its place and size whatever the mode
  for (const id in (user.pin || {})) {
    const p = user.pin[id];
    if (!p || !avail[id]) continue;
    const had = all().find(s => s.id === id);
    rail = rail.filter(s => s.id !== id);
    shelf = shelf.filter(s => s.id !== id);
    if (hero && hero.id === id) hero = null;
    const spec = { id: id, size: p.size, flavor: had ? had.flavor : "", pinned: true };
    if (p.where === "hero") {
      if (hero) rail.unshift({ id: hero.id, size: SMALL.indexOf(hero.id) >= 0 ? "S" : "C", flavor: hero.flavor });
      hero = spec;
    } else rail.unshift(spec);
  }
  // minimized by you: always the shelf, never auto-restored
  for (const id in (user.min || {})) {
    if (!user.min[id] || (user.pin || {})[id] || !avail[id]) continue;
    if (hero && hero.id === id) hero = null;
    rail = rail.filter(s => s.id !== id);
    shelf = shelf.filter(s => s.id !== id);
    shelf.unshift({ id: id, size: "M", flavor: "", mine: true });
  }
  if (ctx.mode !== "gaming" && rail.length > 4) {
    shelf = rail.slice(4).map(s => ({ id: s.id, size: "M", flavor: "" })).concat(shelf);
    rail = rail.slice(0, 4);
  }
  if (ctx.mode !== "gaming") {
    const placed = all().map(s => s.id);
    for (const id of ORDER) if (present(id) && placed.indexOf(id) < 0) shelf.push({ id: id, size: "M", flavor: "" });
  }
  return { hero: hero, rail: rail, shelf: shelf };
}

// Geometry. `g` = { top, left, right, bottom, gap }: the edges windows sit at
// (bar + Hyprland's gaps_out, see Desktop.qml) and the gap between cards. The
// mode chip takes the top-left corner; hero and rail start one gap below it;
// the shelf sits on the bottom edge and wraps upward into more rows.
var CHIP_H = 26;
function widthOf(spec) { return spec.size === "L" || spec.size === "F" ? 760 : 360; }

// heights: {id: px} measured from the cards; returns {id: {x, y, w, slot, spec}}
function place(lay, screenW, screenH, heights, g) {
  const out = {};
  const h = id => heights[id] || 140;
  const top = g.top + CHIP_H + g.gap;
  if (lay.hero) out[lay.hero.id] = { x: g.left, y: top, w: widthOf(lay.hero), slot: "hero", spec: lay.hero };
  let y = top;
  for (const s of lay.rail) {
    const w = widthOf(s);
    out[s.id] = { x: screenW - g.right - w, y: y, w: w, slot: "rail", spec: s };
    y += h(s.id) + g.gap;
  }
  const perRow = Math.max(1, Math.floor((screenW - g.left - g.right + g.gap) / (360 + g.gap)));
  const rowH = Math.max(0, ...lay.shelf.map(s => h(s.id)));
  lay.shelf.forEach((s, i) => {
    const row = Math.floor(i / perRow), col = i % perRow;
    out[s.id] = { x: g.left + col * (360 + g.gap), y: screenH - g.bottom - rowH - row * (rowH + g.gap), w: 360, slot: "shelf", spec: s };
  });
  return out;
}

// Tests for home/quickshell/desktop/Layout.js (the desktop's card layout):
//   python3 tests/run.py desk-layout     (or: node tests/quickshell/desk-layout.test.js)
// Layout.js is a QML library, so its `.pragma library` line is stripped first.
// require()ing this file runs the tests and EXPORTS { passed, failed, results } without printing or exiting; running it as a
// script prints a summary and sets the exit code.
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "..", "home", "quickshell", "desktop", "Layout.js"), "utf8").replace(/^\.pragma library\s*$/m, "");
const L = new Function(src + "\nreturn { layout, recipeCards, place, chipY };")();

let passed = 0, failed = 0;
const failures = [];
const results = [];
function test(name, fn) {
  try { fn(); passed++; results.push({ name, ok: true }); }
  catch (e) { failed++; failures.push("  FAIL  " + name + "\n        " + e.message); results.push({ name, ok: false, error: e.message }); }
}
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error((msg || "differs") + ": expected " + JSON.stringify(b) + ", got " + JSON.stringify(a));
}

const ALL = { next: true, weather: true, kanban: true, pomo: true, printer: true, music: true, phone: true, server: true, calendar: true };
const lay = (mode, extra = {}) => L.layout(Object.assign({ mode, available: ALL, musicActive: false, printerActive: false, user: { min: {}, pin: {} } }, extra));
const ids = list => list.map(s => s.id);
const where = (l, id) => l.hero && l.hero.id === id ? "hero" : ids(l.rail).includes(id) ? "rail" : ids(l.shelf).includes(id) ? "shelf" : "none";

// ---------------------------------------------------------------- recipes
test("morning recipe: next is the hero, weather/kanban/pomo on the rail", () => {
  const l = lay("morning");
  eq(l.hero.id, "next");
  eq(ids(l.rail), ["weather", "kanban", "pomo"]);
  eq(where(l, "server"), "shelf");
});
test("music only shows while something plays", () => {
  eq(where(lay("morning"), "music"), "none");
  eq(where(lay("morning", { musicActive: true }), "music"), "shelf");
});

// ---------------------------------------------------------------- your pins and minimizes
test("a minimized card goes to the shelf, even the recipe's hero", () => {
  const l = lay("morning", { user: { min: { next: true }, pin: {} } });
  eq(l.hero, null);
  eq(where(l, "next"), "shelf");
});
test("a pinned card holds its place across modes", () => {
  const l = lay("deep_work", { user: { min: {}, pin: { server: { where: "rail", size: "C" } } } });
  eq(where(l, "server"), "rail");
});

// ---------------------------------------------------------------- mode pins (settings.toml [modes.<name>] pinned)
test("a mode pin the recipe would shelve goes to the top of the rail", () => {
  const l = lay("morning", { modePinned: ["server"] });
  eq(l.rail[0].id, "server");
  eq(l.rail[0].modePinned, true);
  eq(where(l, "server"), "rail");
  eq(ids(l.shelf).includes("server"), false);
});
test("a mode pin the recipe already shows stays where it is", () => {
  const l = lay("morning", { modePinned: ["next", "kanban"] });
  eq(l.hero.id, "next");
  eq(l.hero.modePinned, true);
  eq(where(l, "kanban"), "rail");
});
test("small live cards keep their small size when mode-pinned", () => {
  const l = lay("morning", { modePinned: ["phone"] });
  eq(l.rail[0], { id: "phone", size: "S", flavor: "", modePinned: true });
});
test("mode pins survive the rail's 4-card limit; recipe cards overflow instead", () => {
  const l = lay("printing", { modePinned: ["server", "calendar"] });   // recipe rail already has 4
  eq(ids(l.rail).slice(0, 2), ["server", "calendar"]);
  eq(l.rail.length, 4);
});
test("mode pins keep their settings order", () => {
  eq(ids(lay("morning", { modePinned: ["server", "calendar"] }).rail).slice(0, 2), ["server", "calendar"]);
});
test("you can still minimize a mode pin while in the mode", () => {
  const l = lay("morning", { modePinned: ["server"], user: { min: { server: true }, pin: {} } });
  eq(where(l, "server"), "shelf");
});
test("unknown ids and cards with nothing to show are ignored", () => {
  const l = lay("morning", { modePinned: ["bogus", "music"] });
  eq(where(l, "music"), "none");
  eq(ids(l.rail), ["weather", "kanban", "pomo"]);
});
test("only the current mode's pins apply (none given: the recipe alone)", () => {
  eq(ids(lay("deep_work").rail), ids(lay("deep_work", { modePinned: [] }).rail));
});

test("a mode's default pins are the cards its recipe shows (hero, then rail)", () => {
  eq(L.recipeCards("morning"), ["next", "weather", "kanban", "pomo"]);
  eq(L.recipeCards("class"), ["next", "kanban"]);
  eq(L.recipeCards("deep_work"), ["pomo", "kanban", "next"]);
  eq(L.recipeCards("gaming"), ["phone", "printer", "music"]);
  eq(L.recipeCards("nope"), []);
});
test("default pins don't move anything: the layout equals the recipe's", () => {
  for (const m of ["morning", "class", "deep_work", "printing", "music", "evening", "gaming"]) {
    const a = lay(m, { musicActive: true, printerActive: true });
    const b = lay(m, { musicActive: true, printerActive: true, modePinned: L.recipeCards(m) });
    eq([b.hero && b.hero.id, ids(b.rail), ids(b.shelf)], [a.hero && a.hero.id, ids(a.rail), ids(a.shelf)], m);
  }
});

// ---------------------------------------------------------------- geometry
const G = { top: 44, left: 12, right: 12, bottom: 12, gap: 12 };
test("hero and rail start at the top edge; the mode chip sits one gap under the hero", () => {
  const p = L.place(lay("morning"), 2256, 1504, { next: 300 }, G);
  eq(p.weather.y, G.top, "first rail card");
  eq(p.next.y, G.top, "hero");
  eq(L.chipY(lay("morning"), { next: 300 }, G), G.top + 300 + G.gap, "chip");
});
test("with no hero (gaming) the mode chip stays at the top edge", () => {
  eq(L.chipY(lay("gaming"), {}, G), G.top);
});
test("cards are one gap apart, the same as from the screen edges", () => {
  const h = { weather: 100, kanban: 200, pomo: 80, server: 30, phone: 30 };
  const p = L.place(lay("morning"), 2256, 1504, h, G);
  eq(p.kanban.y - (p.weather.y + h.weather), G.gap, "rail spacing");
  eq(p.pomo.y - (p.kanban.y + h.kanban), G.gap, "rail spacing");
  eq(2256 - (p.weather.x + p.weather.w), G.right, "rail to the right edge");
  const shelf = lay("morning").shelf.map(s => p[s.id]).filter(Boolean).sort((a, b) => a.x - b.x);
  eq(shelf[1].x - (shelf[0].x + shelf[0].w), G.gap, "shelf spacing");
  eq(shelf[0].x, G.left, "shelf to the left edge");
});

if (require.main === module) {
  for (const f of failures) console.log(f);
  console.log(`${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
} else {
  module.exports = { passed, failed, results };
}

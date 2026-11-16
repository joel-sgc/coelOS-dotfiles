// Tests for Layout.js:  node home/quickshell/overview/Layout.test.js
// (Layout.js is a QML library, so its `.pragma library` line is stripped first.)
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "Layout.js"), "utf8").replace(/^\.pragma library\s*$/m, "");
const L = new Function(src + "\nreturn { ROW, ROWS, rowOf, colOf, idOf, parseRemembered, rowsOf, appName };")();

let passed = 0, failed = 0;
const failures = [];
function test(name, fn) {
  try { fn(); passed++; } catch (e) { failed++; failures.push("  FAIL  " + name + "\n        " + e.message); }
}
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error((msg || "differs") + ": expected " + JSON.stringify(b) + ", got " + JSON.stringify(a));
}
const client = (address, ws, extra = {}) =>
  Object.assign({ address, class: "app", title: address, workspace: { id: ws }, monitor: 0, at: [0, 0], size: [800, 600], floating: false }, extra);
const deskIds = row => row.desks.map(d => d.id);
const rep = row => row.desks.filter(d => d.rep).map(d => d.id);

// ---------------------------------------------------------------- ids
test("ids map to rows and 1-based columns, and back", () => {
  eq([1, 100, 101, 200, 401, 500].map(L.rowOf), [0, 0, 1, 1, 4, 4]);
  eq([1, 100, 101, 205].map(L.colOf), [1, 100, 1, 5]);
  for (let id = 1; id <= 500; id++) eq(L.idOf(L.rowOf(id), L.colOf(id)), id, "id " + id);
});

// ---------------------------------------------------------------- remembered
test("parseRemembered reads grid.lua's snapshot", () => {
  eq(L.parseRemembered("1,,,307,"), [1, 0, 0, 307, 0]);
  eq(L.parseRemembered("3,104,,,404"), [3, 104, 0, 0, 404]);
});
test("parseRemembered ignores anything unusable", () => {
  eq(L.parseRemembered(""), [0, 0, 0, 0, 0]);
  eq(L.parseRemembered(null), [0, 0, 0, 0, 0]);
  eq(L.parseRemembered("abc,-4,0,2.5x,"), [0, 0, 0, 0, 0]);
  eq(L.parseRemembered("205,1,,,"), [0, 0, 0, 0, 0], "a workspace listed under the wrong row is dropped");
  eq(L.parseRemembered("1,2,3,4,5,6,7"), [1, 0, 0, 0, 0], "extra entries are ignored");
});

// ---------------------------------------------------------------- shape
test("always five rows, labelled r1..r5, each with at least one desk", () => {
  const rows = L.rowsOf([], {});
  eq(rows.map(r => r.label), ["r1", "r2", "r3", "r4", "r5"]);
  rows.forEach(r => { eq(r.desks.length, 1); eq(r.desks[0].rep, true); eq(r.desks[0].windows.length, 0); });
  eq(rows.map(r => r.desks[0].id), [1, 101, 201, 301, 401]);
  eq(L.rowsOf(null, undefined).length, 5);
});

test("a desk carries its workspace's windows", () => {
  const rows = L.rowsOf([client("a", 2), client("b", 2), client("c", 103)], { focusedId: 2 });
  eq(deskIds(rows[0]), [2, 3]);
  eq(rows[0].desks[0].windows.map(w => w.address), ["a", "b"]);
  eq(deskIds(rows[1]), [103, 104]);
});

test("a row shows every workspace that has windows, in column order", () => {
  const rows = L.rowsOf([client("a", 7), client("b", 2), client("c", 5)], { focusedId: 2 });
  eq(deskIds(rows[0]), [2, 5, 7, 8]);
});

test("windows are placed relative to the monitor", () => {
  const rows = L.rowsOf([client("a", 1, { at: [2356, 148], size: [1000, 500] })], { focusedId: 1, monX: 2256, monY: 100 });
  const w = rows[0].desks[0].windows[0];
  eq([w.x, w.y, w.w, w.h], [100, 48, 1000, 500]);
});

test("only windows on the monitor being shown count", () => {
  const rows = L.rowsOf([client("a", 1), client("b", 1, { monitor: 1 })], { focusedId: 1, monitorId: 0 });
  eq(rows[0].desks[0].windows.map(w => w.address), ["a"]);
  eq(L.rowsOf([client("a", 1, { monitor: 5 })], { focusedId: 1 })[0].desks[0].windows.length, 1, "no monitor given: all of them");
});

test("floating windows come after tiled ones so they are drawn on top", () => {
  const rows = L.rowsOf([client("f", 1, { floating: true }), client("t1", 1), client("t2", 1)], { focusedId: 1 });
  eq(rows[0].desks[0].windows.map(w => w.address), ["f", "t1", "t2"].sort((a, b) => (a === "f") - (b === "f")));
});

// ---------------------------------------------------------------- which desk is "as you left it"
test("on your own row the representative is the workspace you are on, even when empty", () => {
  const rows = L.rowsOf([client("a", 1)], { focusedId: 4 });
  eq(rep(rows[0]), [4]);
  eq(deskIds(rows[0]), [1, 4]);
  eq(rows.map(r => r.current), [true, false, false, false, false]);
});

test("other rows use the workspace the grid remembers", () => {
  const rows = L.rowsOf([client("a", 1), client("b", 103), client("c", 105)], { focusedId: 1, remembered: "1,105,,," });
  eq(rep(rows[1]), [105]);
  eq(deskIds(rows[1]), [103, 105, 106]);
});

test("a remembered workspace with no windows is still shown", () => {
  const rows = L.rowsOf([client("b", 103)], { focusedId: 1, remembered: "1,108,,," });
  eq(deskIds(rows[1]), [103, 108]);
  eq(rep(rows[1]), [108]);
});

test("without a memory, the first workspace with windows represents the row", () => {
  const rows = L.rowsOf([client("a", 1), client("b", 207), client("c", 203)], { focusedId: 1 });
  eq(rep(rows[2]), [203]);
});

test("an empty row is represented by its first column", () => {
  const rows = L.rowsOf([client("a", 1)], { focusedId: 1 });
  eq(rep(rows[3]), [301]);
  eq(deskIds(rows[3]), [301]);
});

test("a scratchpad up (no focused workspace): no row is current, memory is used", () => {
  const rows = L.rowsOf([client("a", 1)], { focusedId: -98, remembered: "5,,,," });
  eq(rows.map(r => r.current), [false, false, false, false, false]);
  eq(rep(rows[0]), [5]);
});

test("each row has exactly one representative", () => {
  L.rowsOf([client("a", 1), client("b", 2), client("c", 101)], { focusedId: 2, remembered: "1,101,,," })
    .forEach(r => eq(r.desks.filter(d => d.rep).length, 1, r.label));
});

// ---------------------------------------------------------------- what is left out
test("scratchpad, hidden, unmapped and past-the-grid windows are left out", () => {
  const rows = L.rowsOf([
    client("a", -98), client("b", 0), client("c", 501), client("d", 1, { mapped: false }),
    client("e", 1, { hidden: true }), client("ok", 1),
  ], { focusedId: 1 });
  eq(rows[0].desks[0].windows.map(w => w.address), ["ok"]);
  eq(rows.reduce((n, r) => n + r.desks.reduce((m, d) => m + d.windows.length, 0), 0), 1);
});

test("missing or zero fields still give a usable window", () => {
  const w = L.rowsOf([{ address: "x", initialClass: "firefox", workspace: { id: 1 } }], { focusedId: 1 })[0].desks[0].windows[0];
  eq([w.cls, w.title, w.w, w.h], ["firefox", "", 1, 1]);
});

test("null entries and clients without a workspace are ignored", () => {
  eq(L.rowsOf([null, {}, { address: "x" }, client("ok", 1)], { focusedId: 1 })[0].desks[0].windows.length, 1);
});

// ---------------------------------------------------------------- names and the spare workspace
test("window classes get readable names", () => {
  const n = L.appName;
  eq(n("zen"), "Zen Browser"); eq(n("code"), "VS Code"); eq(n("kitty"), "Kitty");
  eq(n("chrome-cad.onshape.com__-Default"), "Onshape");
  eq(n("chrome-mail.google.com__u_0-Default"), "Google");
  eq(n("org.kde.dolphin"), "Files");
  eq(n("org.example.some-tool"), "Some Tool");
  eq(n("my_app"), "My App");
  eq(n(""), ""); eq(n(undefined), "");
});

test("each window carries its readable name", () => {
  const rows = L.rowsOf([client("a", 1, { class: "zen" })], { focusedId: 1 });
  eq(rows[0].desks[0].windows[0].name, "Zen Browser");
});

test("a row whose last workspace has windows offers the next one, empty", () => {
  const rows = L.rowsOf([client("a", 1), client("b", 3)], { focusedId: 1 });
  eq(deskIds(rows[0]), [1, 3, 4]);
  eq(rows[0].desks[2].windows.length, 0);
  eq(rep(rows[0]), [1]);
});

test("an empty last workspace is left as it is: no extra one", () => {
  const rows = L.rowsOf([client("a", 1)], { focusedId: 4 });     // you are on empty 4
  eq(deskIds(rows[0]), [1, 4]);
  eq(deskIds(rows[2]), [201], "empty rows too");
});

test("no spare workspace past the end of a row", () => {
  const rows = L.rowsOf([client("a", 100), client("b", 500)], { focusedId: 100 });
  eq(deskIds(rows[0]), [100]);
  eq(deskIds(rows[4]), [500]);
});

// ---------------------------------------------------------------- fuzz
test("fuzz: 3000 random worlds keep every invariant", () => {
  let s = 4242;
  const rand = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  const ri = (lo, hi) => lo + Math.floor(rand() * (hi - lo + 1));
  for (let n = 0; n < 3000; n++) {
    const list = [];
    for (let i = ri(0, 16); i > 0; i--) {
      const id = rand() < 0.15 ? ri(-100, 0) : rand() < 0.15 ? ri(501, 800) : ri(1, 500);
      list.push(client("c" + n + "_" + i, id, { monitor: ri(0, 1), mapped: rand() < 0.9, hidden: rand() < 0.1, floating: rand() < 0.3 }));
    }
    const focusedId = rand() < 0.2 ? ri(-100, 0) : ri(1, 520);
    const mem = [0, 1, 2, 3, 4].map(r => rand() < 0.5 ? ri(1, 600) : "").join(",");
    const rows = L.rowsOf(list, { focusedId, remembered: mem, monitorId: 0 });
    const where = "world " + n;
    eq(rows.length, 5, where);
    const seen = {};
    rows.forEach((r, i) => {
      if (r.desks.length < 1) throw new Error(where + " row " + i + " has no desk");
      if (r.desks.filter(d => d.rep).length !== 1) throw new Error(where + " row " + i + " representative count");
      r.desks.forEach((d, k) => {
        if (L.rowOf(d.id) !== i) throw new Error(where + " desk " + d.id + " in the wrong row");
        if (d.col !== L.colOf(d.id)) throw new Error(where + " wrong column");
        if (k > 0 && !(d.id > r.desks[k - 1].id)) throw new Error(where + " desks not sorted/unique");
        d.windows.forEach(w => { if (seen[w.address]) throw new Error(where + " window twice"); seen[w.address] = true; });
        const floatSeen = d.windows.findIndex(w => w.floating);
        if (floatSeen >= 0 && d.windows.slice(floatSeen).some(w => !w.floating)) throw new Error(where + " floating not last");
      });
    });
    const expected = list.filter(c => c.workspace.id >= 1 && L.rowOf(c.workspace.id) < 5 && c.mapped !== false && c.hidden !== true && c.monitor === 0).length;
    eq(Object.keys(seen).length, expected, where + " windows kept");
    const focusedInGrid = focusedId >= 1 && L.rowOf(focusedId) < 5;
    eq(rows.filter(r => r.current).length, focusedInGrid ? 1 : 0, where + " current row");
    if (focusedInGrid) eq(rows[L.rowOf(focusedId)].desks.filter(d => d.rep)[0].id, focusedId, where + " focused is the representative");
  }
});

failures.forEach(f => console.log(f));
console.log(passed + " passed, " + failed + " failed");
process.exit(failed === 0 ? 0 : 1);

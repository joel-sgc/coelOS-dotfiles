import Quickshell
import Quickshell.Io
import QtQuick
import "../widgets"

// ===== DISPLAYS BACKEND =====
// State + logic behind DisplayModes.qml (ported from example/Display
// Modes.dc.html), driven by the real monitors from `hyprctl monitors all`.
//
// Slot model: the anchor monitor (the internal panel, or the first monitor
// when there is none) stays where it is; every other monitor sits in one
// slot (left / up / right / mirror / off). left/up/right are chains ordered
// outward from the anchor by `seq`, so [ ] just swaps seq with the
// neighbour.
//
// Applying runs `hyprctl keyword monitor` in one batch -- runtime only, so
// a config reload goes back to home/hyprland.nix's rules. While the "keep
// this layout?" countdown runs, a detached watchdog restores the previous
// layout on its own, in case this process dies before answering.
QtObject {
  id: root

  property int revertSeconds: 15

  signal quitRequested()
  // The outputs have finished changing; see LayerNudge.qml.
  signal settled()
  // The keep-or-revert panel is up and the outputs have settled.
  signal confirmShown()

  readonly property var accents: [Pal.purple, Pal.green, Pal.yellow, Pal.cyan, Pal.orange, Pal.red]
  readonly property var slots: [
    ["left", "←", "extend left"], ["up", "↑", "extend up"], ["right", "→", "extend right"],
    ["mirror", "⧉", "mirror laptop"], ["off", "○", "turn off"]
  ]
  readonly property var dirGlyph: ({ left: "←", up: "↑", right: "→" })

  // ----- state -----
  property var monitors: []            // parsed monitors, anchor first
  readonly property var laptop: monitors.length ? monitors[0] : ({ id: "", w: 0, h: 0 })
  property bool ready: false
  property string error: ""
  property string uiName: ""           // monitor the modal is shown on
  property string uiNameStart: ""      // ... when it opened (restored on revert)
  // cfg = { lap: bool (anchor on), a: { id: { slot, seq } } }
  property var cur: null
  property var draft: null
  property var prev: null
  property string phase: "pick"        // pick | applying | confirm
  property int row: 0
  property int seq: 100
  property int left: 0
  property int spin: 0

  readonly property bool applying: phase === "applying"
  readonly property bool confirming: phase === "confirm"

  Component.onCompleted: loadProc.running = true

  // ----- reading monitors -----
  function parseMode(s) {
    const m = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
    return m ? { w: Number(m[1]), h: Number(m[2]), hz: Number(m[3]) } : null;
  }
  function isMirror(r) { return !!r.mirrorOf && r.mirrorOf !== "none" && r.mirrorOf !== -1; }
  function mirrorTarget(r) {
    if (typeof r.mirrorOf === "number") {
      const t = monitors.find(m => m.raw.id === r.mirrorOf);
      return t ? t.id : "";
    }
    return r.mirrorOf;
  }
  function parseMonitor(r, i) {
    // A disabled output reports no mode; fall back to its best available one.
    const avail = (r.availableModes || []).map(parseMode).filter(Boolean);
    let w = r.width, h = r.height, hz = r.refreshRate;
    if (!(w > 0) || !(h > 0)) {
      if (avail.length) { w = avail[0].w; h = avail[0].h; hz = avail[0].hz; }
    }
    const mk = (mw, mh, mhz) => ({
      w: mw, h: mh, hz: mhz,
      str: mw + "x" + mh + "@" + Math.round(mhz * 1000) / 1000,
      spec: mw + "×" + mh + " @" + Math.round(mhz)
    });
    // Every distinct mode, biggest first. The mode in use keeps its exact
    // refresh rate (e.g. 59.999) so "no change" stays a no-op.
    const seen = {}, modes = [];
    avail.forEach(a => {
      const k = a.w + "x" + a.h + "@" + a.hz;
      if (!seen[k]) { seen[k] = true; modes.push(mk(a.w, a.h, a.hz)); }
    });
    modes.sort((p, q) => q.w * q.h - p.w * p.h || q.hz - p.hz);
    const curMode = mk(w, h, hz), ci = modes.findIndex(x => x.w === w && x.h === h && Math.abs(x.hz - hz) < 0.5);
    if (ci >= 0) modes[ci] = curMode; else modes.unshift(curMode);
    const scale = r.scale > 0 ? r.scale : 1, tr = r.transform || 0;
    const internal = /^(eDP|LVDS|DSI)/i.test(r.name);
    const name = ((r.make || "") + " " + (r.model || "")).trim() || r.description || r.name;
    const m = {
      id: r.name, internal: internal, raw: r,
      icon: internal ? "laptop" : "monitor",
      color: internal ? Pal.blue : accents[(i - 1) % accents.length],
      model: internal ? "built-in" : name,
      mode: curMode.str, modes: modes, scale: scale, transform: tr,
      // physical panel shape, from the EDID size in mm (0 if unknown)
      pa: r.physicalWidth > 0 && r.physicalHeight > 0 ? r.physicalWidth / r.physicalHeight : 0
    };
    const d = dimsOf(m, curMode);
    m.w = d.w; m.h = d.h;
    return m;
  }
  // Logical size of a monitor in a given mode: scaled, and swapped when rotated 90/270.
  function dimsOf(m, mode) {
    const swap = m.transform % 2 === 1;
    return { w: Math.round((swap ? mode.h : mode.w) / m.scale), h: Math.round((swap ? mode.w : mode.h) / m.scale) };
  }
  function modeOf(m, cfg) {
    return m.modes.find(x => x.str === cfg.mode[m.id]) || m.modes.find(x => x.str === m.mode) || m.modes[0];
  }
  function dims(m, cfg) { return dimsOf(m, modeOf(m, cfg)); }
  // A mode whose shape is off from the panel's by more than 10% gets
  // stretched to fill it (a 16:9 signal on a tall panel, say).
  function stretched(m, mode) { return m.pa > 0 && Math.abs((mode.w / mode.h) / m.pa - 1) > 0.1; }
  function bestFit(m) { return m.modes.find(x => !stretched(m, x)) || null; }
  function load(text) {
    let raw = [];
    try { raw = JSON.parse(text); } catch (e) { raw = []; }
    if (!raw.length) { quitRequested(); return; }
    // anchor first: the internal panel if there is one, else the first output
    const ai = Math.max(0, raw.findIndex(r => /^(eDP|LVDS|DSI)/i.test(r.name)));
    raw = [raw[ai], ...raw.filter((_, i) => i !== ai)];
    monitors = raw.map((r, i) => parseMonitor(r, i));
    cur = deriveConfig();
    // Open with any stretched monitor already switched to a mode that fits
    // its panel (shown as a pending change, not applied until you apply).
    const d = clone(cur);
    monitors.forEach(m => {
      if (stretched(m, modeOf(m, d))) { const f = bestFit(m); if (f) d.mode[m.id] = f.str; }
    });
    draft = d;
    uiNameStart = anchorName(cur);
    uiName = uiNameStart;
    row = monitors.length > 1 ? 1 : 0;
    ready = true;
  }
  // Slots from where the monitors really are right now.
  function deriveConfig() {
    const a = monitors[0], ex = monitors.slice(1), cfg = { lap: !a.raw.disabled, a: {}, mode: {} };
    monitors.forEach(m => { cfg.mode[m.id] = m.mode; });
    const ax = a.raw.x, ay = a.raw.y;
    ex.forEach(m => {
      const r = m.raw;
      let slot = "right";
      if (r.disabled) slot = "off";
      else if (isMirror(r)) slot = "mirror";
      else if (cfg.lap && r.x + m.w <= ax) slot = "left";
      else if (cfg.lap && r.x < ax + a.w && r.y + m.h <= ay) slot = "up";
      cfg.a[m.id] = { slot: slot, seq: 0 };
    });
    let n = 0;
    ["left", "right", "up"].forEach(dir => {
      ex.filter(m => cfg.a[m.id].slot === dir)
        .sort((p, q) => dir === "right" ? p.raw.x - q.raw.x : dir === "left" ? q.raw.x - p.raw.x : q.raw.y - p.raw.y)
        .forEach(m => { cfg.a[m.id].seq = ++n; });
    });
    ex.forEach(m => { if (!cfg.a[m.id].seq) cfg.a[m.id].seq = ++n; });
    return cfg;
  }

  // ----- layout math -----
  function clone(c) { return JSON.parse(JSON.stringify(c)); }
  function exts() { return monitors.slice(1); }
  function chain(cfg, dir) {
    return exts().filter(m => cfg.a[m.id].slot === dir).sort((x, y) => cfg.a[x.id].seq - cfg.a[y.id].seq);
  }
  // Everything is centered: monitors in the left/right row share one
  // horizontal center line (the anchor's, or y=0 without it), and the "up"
  // stack is centered over the anchor, or over the row without it. The
  // result is shifted so the top-left corner is 0,0.
  function layout(cfg) {
    const D = {};
    monitors.forEach(m => { D[m.id] = dims(m, cfg); });
    const ent = (m, x, y, idx, dir) => ({ m: m, x: x, y: y, w: D[m.id].w, h: D[m.id].h, mode: modeOf(m, cfg), idx: idx, dir: dir });
    const placed = [], cy = cfg.lap ? D[laptop.id].h / 2 : 0;
    if (cfg.lap) placed.push(ent(laptop, 0, 0, 0, null));
    let x = 0;
    chain(cfg, "left").forEach((m, i) => { x -= D[m.id].w; placed.push(ent(m, x, Math.round(cy - D[m.id].h / 2), i + 1, "left")); });
    x = cfg.lap ? D[laptop.id].w : 0;
    chain(cfg, "right").forEach((m, i) => { placed.push(ent(m, x, Math.round(cy - D[m.id].h / 2), i + 1, "right")); x += D[m.id].w; });
    const top = placed.length ? Math.min(...placed.map(p => p.y)) : 0;
    const cx = cfg.lap ? D[laptop.id].w / 2
      : placed.length ? (Math.min(...placed.map(p => p.x)) + Math.max(...placed.map(p => p.x + p.w))) / 2 : 0;
    let y = top;
    chain(cfg, "up").forEach((m, i) => { y -= D[m.id].h; placed.push(ent(m, Math.round(cx - D[m.id].w / 2), y, i + 1, "up")); });
    if (placed.length) {
      const dx = -Math.min(...placed.map(p => p.x)), dy = -Math.min(...placed.map(p => p.y));
      placed.forEach(p => { p.x += dx; p.y += dy; });
    }
    const mirrored = cfg.lap ? exts().filter(m => cfg.a[m.id].slot === "mirror") : [];
    const off = exts().filter(m => cfg.a[m.id].slot === "off" || (!cfg.lap && cfg.a[m.id].slot === "mirror"));
    return { placed: placed, mirrored: mirrored, off: off };
  }
  function key(cfg) {
    const L = layout(cfg);
    return [cfg.lap, ...L.placed.map(p => p.m.id + "@" + p.x + "," + p.y + "#" + p.mode.str),
            "m:" + L.mirrored.map(m => m.id + "#" + modeOf(m, cfg).str), "o:" + L.off.map(m => m.id)].join("|");
  }
  function summary(cfg) {
    const L = layout(cfg), on = L.placed.length + L.mirrored.length;
    const parts = ["left", "up", "right"].map(d => {
      const c = chain(cfg, d);
      return c.length ? dirGlyph[d] + " " + c.map(m => m.id).join(" ") : "";
    }).filter(Boolean);
    return on + " on" + (parts.length ? " · " + parts.join(" · ") : "")
      + (L.mirrored.length ? " · ⧉ " + L.mirrored.length : "") + (cfg.lap ? "" : " · laptop off");
  }
  function trArg(m) { return m.transform ? ",transform," + m.transform : ""; }
  // `hyprctl --batch` commands for a layout. Outputs that stay on come first
  // so there is never a moment with nothing enabled.
  function commands(cfg) {
    const L = layout(cfg), out = [];
    L.placed.forEach(p => out.push("keyword monitor " + p.m.id + "," + p.mode.str + "," + p.x + "x" + p.y + "," + p.m.scale + trArg(p.m)));
    L.mirrored.forEach(m => out.push("keyword monitor " + m.id + "," + modeOf(m, cfg).str + ",auto," + m.scale + trArg(m) + ",mirror," + laptop.id));
    if (!cfg.lap) out.push("keyword monitor " + laptop.id + ",disable");
    L.off.forEach(m => out.push("keyword monitor " + m.id + ",disable"));
    return out;
  }
  // The layout as it was when the modal opened, from the raw positions.
  function restoreCommands() {
    const on = [], mirrors = [], offs = [];
    monitors.forEach(m => {
      const r = m.raw;
      if (r.disabled) offs.push("keyword monitor " + m.id + ",disable");
      else if (isMirror(r)) mirrors.push("keyword monitor " + m.id + "," + m.mode + ",auto," + m.scale + trArg(m) + ",mirror," + mirrorTarget(r));
      else on.push("keyword monitor " + m.id + "," + m.mode + "," + r.x + "x" + r.y + "," + m.scale + trArg(m));
    });
    return [...on, ...mirrors, ...offs];
  }
  function rowIds() { return monitors.map(m => m.id); }
  function rowOpts(id, d) {
    if (id === laptop.id) return ["on", "off"];
    return slots.filter(s => s[0] !== "mirror" || d.lap).map(s => s[0]);
  }
  function presetConfig(id) {
    const t = clone(draft), ex = exts();
    if (id === "internal") { t.lap = true; ex.forEach((m, i) => { t.a[m.id] = { slot: "off", seq: i }; }); }
    else if (id === "external") { t.lap = false; ex.forEach((m, i) => { t.a[m.id] = { slot: "right", seq: i }; }); }
    else { t.lap = true; ex.forEach((m, i) => { t.a[m.id] = { slot: id, seq: i }; }); }
    return t;
  }

  // ----- derived view models (what DisplayModes.qml binds to) -----
  readonly property var cl: draft ? layout(draft) : { placed: [], mirrored: [], off: [] }
  readonly property bool valid: cl.placed.length > 0
  readonly property bool changed: draft ? key(draft) !== key(cur) : false
  readonly property string selId: { const ids = rowIds(); return ids.length ? ids[Math.min(row, ids.length - 1)] : ""; }

  // Canvas boxes as fractions (0..1) of the canvas, keyed by monitor id so
  // the delegates persist and animate when a monitor moves slots.
  readonly property var canvas: {
    const out = { byId: ({}), bw: 0, bh: 0 };
    if (!valid) return out;
    const P = cl.placed;
    const minX = Math.min(...P.map(p => p.x)), minY = Math.min(...P.map(p => p.y));
    const maxX = Math.max(...P.map(p => p.x + p.w)), maxY = Math.max(...P.map(p => p.y + p.h));
    const bw = maxX - minX, bh = maxY - minY, CW = 100, CH = 36;
    const sc = Math.min(CW * 0.9 / bw, CH * 0.82 / bh), ox = (CW - bw * sc) / 2, oy = (CH - bh * sc) / 2;
    P.forEach(p => {
      const nm = p.m.internal ? cl.mirrored.length : 0;
      out.byId[p.m.id] = {
        sub: p.m.internal ? (nm ? "⧉ " + nm + " mirrored" : "anchor") : dirGlyph[p.dir] + p.idx + "  " + p.x + "," + p.y,
        l: (ox + (p.x - minX) * sc) / CW, t: (oy + (p.y - minY) * sc) / CH,
        w: p.w * sc / CW, h: p.h * sc / CH
      };
    });
    out.bw = bw; out.bh = bh;
    return out;
  }
  readonly property string canvasMeta: valid ? canvas.bw + "×" + canvas.bh + " logical" : "invalid"
  readonly property color canvasMetaColor: valid ? Pal.muted : Pal.red
  readonly property string sideNote: {
    const offNames = [...(draft && !draft.lap ? [laptop.id] : []), ...cl.off.map(m => m.id)];
    const mir = cl.mirrored.map(m => m.id);
    return [mir.length ? "⧉ " + mir.join(", ") + " mirror the laptop" : "",
            offNames.length ? "○ off: " + offNames.join(", ") : ""].filter(Boolean).join("   ");
  }

  readonly property var rows: {
    if (!draft) return [];
    const d = draft, ids = rowIds(), out = [];
    ids.forEach((id, ri) => {
      const m = monitors.find(x => x.id === id), p = cl.placed.find(x => x.m.id === id);
      let pos = "off", posColor = Pal.muted;
      if (p) { pos = p.x + "," + p.y; posColor = Pal.fg; }
      else if (cl.mirrored.some(x => x.id === id)) { pos = "mirrors " + laptop.id; posColor = Pal.dim; }
      const md = modeOf(m, d);
      let opts = [], reorder = false, arrows = null;
      if (id === laptop.id) {
        opts = [
          { k: "on", label: "● on", tip: "keep laptop panel on", selected: d.lap, dimmed: false },
          { k: "off", label: "○ off", tip: "turn laptop panel off", selected: !d.lap, dimmed: false }
        ];
      } else {
        const slot = d.a[id].slot, c = dirGlyph[slot] ? chain(d, slot) : [], ci = c.findIndex(x => x.id === id);
        opts = slots.map(s => ({
          k: s[0], label: s[1] + " " + s[0] + (slot === s[0] && c.length > 1 ? " ·" + (ci + 1) : ""), tip: s[2],
          selected: slot === s[0], dimmed: s[0] === "mirror" && !d.lap
        }));
        reorder = c.length > 1;
        // Chevrons point the way the monitor moves: ‹ › for the left/right
        // chains, ⌃ ⌄ for the up stack. nudge(-1) moves it toward the
        // laptop, nudge(+1) away: toward-the-laptop is rightwards on the
        // left chain, leftwards on the right chain, downwards on the up stack.
        const noToward = ci <= 0, noAway = ci >= c.length - 1;
        const firstDelta = slot === "right" ? -1 : 1;
        const off = dl => dl < 0 ? noToward : noAway;
        const glyphs = slot === "up" ? ["⌃", "⌄"] : ["‹", "›"];
        arrows = [{ glyph: glyphs[0], delta: firstDelta, off: off(firstDelta) },
                  { glyph: glyphs[1], delta: -firstDelta, off: off(-firstDelta) }];
      }
      out.push({ id: id, icon: m.icon, color: m.color, model: m.model, pos: pos, posColor: posColor,
                 spec: md.spec + (m.scale !== 1 ? " ×" + m.scale : ""),
                 warn: stretched(m, md), canFit: !!bestFit(m) && bestFit(m).str !== md.str,
                 modeChanged: md.str !== m.mode, canCycle: m.modes.length > 1,
                 opts: opts, sel: ri === Math.min(row, ids.length - 1), reorder: reorder, arrows: arrows });
    });
    return out;
  }
  readonly property var presets: {
    if (!draft || monitors.length < 2) return [];
    const dk = key(draft);
    return [["left", "← all left"], ["up", "↑ all up"], ["right", "→ all right"], ["mirror", "⧉ mirror all"],
            ["internal", "laptop only"], ["external", "externals only"]]
      .map(([id, label]) => ({ id: id, label: label, on: key(presetConfig(id)) === dk }));
  }
  readonly property var cmd: draft ? commands(draft).map(c => "hyprctl " + c) : []
  readonly property string diffLabel: error ? error : !valid ? "keep at least one display on" : changed ? "changed" : "matches current"
  readonly property color diffColor: error || !valid ? Pal.red : changed ? Pal.yellow : Pal.muted
  readonly property string countLabel: monitors.length + " connected"
  readonly property string spinGlyph: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[spin % 10]

  // Applying / confirm panel.
  readonly property var cf: applying
    ? { legend: "applying", legendColor: Pal.yellow, meta: spinGlyph, border: Pal.faint, icon: "arrows-clockwise", color: Pal.yellow,
        title: "arranging displays…", sub: "screens may flicker for a moment", pct: 0, barColor: Pal.yellow }
    : { legend: "keep this layout?", legendColor: Pal.blue, meta: "reverting in " + left + "s", border: Pal.blue, icon: "check-circle", color: Pal.green,
        title: cur ? summary(cur) : "", sub: "if you can't see this, wait and it goes back to: " + (prev ? summary(prev) : "the last layout") + ".",
        pct: left / revertSeconds, barColor: left <= 5 ? Pal.orange : Pal.blue }

  readonly property var hints: confirming ? [["⏎", "keep"], ["esc", "revert"]]
    : applying ? []
    : [["j k", "monitor"], ["h l · 1-5", "slot"], ["[ ]", "order"], ["m", "mode"], ["⏎", "apply"], ["esc", "close"]]
  readonly property string secondaryLabel: confirming ? "revert" : "cancel"
  readonly property string primaryLabel: confirming ? "keep" : applying ? "applying " + spinGlyph : "apply"
  readonly property color primaryBg: confirming ? Pal.green : applying ? Pal.yellow : valid && changed ? Pal.blue : Pal.muted
  readonly property bool primaryDisabled: applying || !valid
  readonly property real primaryOpacity: confirming || applying || (valid && changed) ? 1 : 0.55

  // ----- actions -----
  function setDraft(fn) {
    const d = clone(draft), s = fn(d, seq);
    draft = d;
    error = "";
    if (s !== undefined) seq = s;
  }
  function selectRow(i) { row = i; }
  // Click on a slot chip: focus that monitor's row, then apply the slot
  // unless the chip is dimmed (mirror with the laptop panel off).
  function pickSlot(id, slot, dimmed) {
    row = rowIds().indexOf(id);
    if (!dimmed) setSlot(id, slot);
  }
  function setSlot(id, slot) {
    setDraft((d, sq) => {
      if (id === laptop.id) {
        d.lap = slot === "on";
        if (!d.lap) Object.keys(d.a).forEach(k => { if (d.a[k].slot === "mirror") d.a[k] = { slot: "right", seq: ++sq }; });
        return sq;
      }
      if (slot === "mirror" && !d.lap) return sq;
      if (d.a[id].slot === slot) return sq;
      d.a[id] = { slot: slot, seq: ++sq };
      return sq;
    });
  }
  function nudge(id, dir) {
    setDraft(d => {
      const slot = d.a[id] && d.a[id].slot;
      if (!dirGlyph[slot]) return;
      const c = chain(d, slot), i = c.findIndex(m => m.id === id), j = i + dir;
      if (j < 0 || j >= c.length) return;
      const o = c[j].id, t = d.a[id].seq;
      d.a[id].seq = d.a[o].seq; d.a[o].seq = t;
    });
  }
  function preset(id) {
    setDraft((d, sq) => {
      const t = presetConfig(id);
      d.lap = t.lap;
      exts().forEach(m => { d.a[m.id] = { slot: t.a[m.id].slot, seq: ++sq }; });
      return sq;
    });
  }

  // Step a monitor through its modes (biggest first), or jump to the best
  // mode that matches the panel's shape.
  function cycleMode(id, delta) {
    const m = monitors.find(x => x.id === id);
    if (!m || m.modes.length < 2) return;
    row = rowIds().indexOf(id);
    setDraft(d => {
      const i = m.modes.findIndex(x => x.str === modeOf(m, d).str);
      d.mode[id] = m.modes[(i + delta + m.modes.length) % m.modes.length].str;
    });
  }
  function fitMode(id) {
    const m = monitors.find(x => x.id === id), f = m && bestFit(m);
    if (!f) return;
    row = rowIds().indexOf(id);
    setDraft(d => { d.mode[id] = f.str; });
  }

  function close() {
    stopTimers();
    quitRequested();
  }
  function stopTimers() { spinTimer.stop(); countdown.stop(); }

  // The monitor the modal lives on: always the laptop panel while it is on,
  // otherwise the highest-resolution monitor that is. Never the focused
  // one, so it doesn't wander when the layout changes.
  function anchorName(cfg) {
    if (cfg.lap) return laptop.id;
    const best = layout(cfg).placed.slice().sort((p, q) => q.mode.w * q.mode.h - p.mode.w * p.mode.h || q.mode.hz - p.mode.hz)[0];
    return best ? best.m.id : laptop.id;
  }

  function apply() {
    if (!valid || phase !== "pick") return;
    if (key(draft) === key(cur)) { close(); return; }
    error = "";
    prev = clone(cur);
    spin = 0;
    // Move to the monitor that will be the anchor *before* the outputs
    // change, so the window is already where it will stay.
    uiName = anchorName(draft);
    phase = "applying";
    spinTimer.start();
    applyProc.command = ["hyprctl", "--batch", commands(draft).join(" ; ")];
    applyProc.running = true;
  }
  function applyDone(text) {
    spinTimer.stop();
    const lines = text.trim().split("\n").map(s => s.trim()).filter(Boolean);
    if (!lines.length || !lines.every(l => l === "ok")) {
      // hyprctl rejected something: put everything back and stay in the modal.
      error = lines.filter(l => l !== "ok").join("; ") || "hyprctl failed";
      restoreProc.quitAfter = false;
      uiName = uiNameStart;
      runRestore();
      phase = "pick";
      return;
    }
    cur = clone(draft);
    settleTimer.start();
    left = revertSeconds;
    phase = "confirm";
    countdown.start();
    startWatchdog();
  }
  function keep() {
    stopTimers();
    watchdog.running = false;
    finish();
  }
  // Leave after a layout change: let the layer surfaces be re-arranged
  // first, then quit.
  function finish() {
    settled();
    quitTimer.start();
  }
  function revert(auto) {
    stopTimers();
    watchdog.running = false;
    uiName = uiNameStart;
    restoreProc.quitAfter = true;
    runRestore();
  }
  function runRestore() {
    restoreProc.command = ["hyprctl", "--batch", restoreCommands().join(" ; ")];
    restoreProc.running = true;
  }
  // Restores the old layout by itself shortly after the countdown ends, even
  // if this process is gone by then. Stopped on keep/revert.
  function startWatchdog() {
    watchdog.command = ["sh", "-c", "sleep " + (revertSeconds + 3) + "; hyprctl --batch \"" + restoreCommands().join(" ; ") + "\""];
    watchdog.running = true;
  }

  // Returns true when the key was consumed.
  function handleKey(k) {
    if (phase === "confirm") {
      if (k === "Enter" || k === "y") keep();
      else if (k === "Escape" || k === "n") revert(false);
      else return false;
      return true;
    }
    if (phase !== "pick") return false;
    if (k === "Escape") { close(); return true; }
    if (!draft) return false;
    const ids = rowIds(), id = ids[Math.min(row, ids.length - 1)], isLap = id === laptop.id;
    const opts = rowOpts(id, draft), curSlot = isLap ? (draft.lap ? "on" : "off") : draft.a[id].slot, oi = opts.indexOf(curSlot);
    if (k === "Enter") apply();
    else if (k === "j" || k === "ArrowDown") row = Math.min(ids.length - 1, row + 1);
    else if (k === "k" || k === "ArrowUp") row = Math.max(0, row - 1);
    else if (k === "l" || k === "ArrowRight") setSlot(id, opts[(oi + 1) % opts.length]);
    else if (k === "h" || k === "ArrowLeft") setSlot(id, opts[(oi - 1 + opts.length) % opts.length]);
    else if (/^[1-5]$/.test(k)) {
      const all = isLap ? ["on", "off"] : slots.map(s => s[0]), pick = all[Number(k) - 1];
      if (pick && opts.includes(pick)) setSlot(id, pick);
    }
    else if (k === "m") cycleMode(id, 1);
    else if (k === "f") fitMode(id);
    else if (k === "[") nudge(id, -1);
    else if (k === "]") nudge(id, 1);
    else return false;
    return true;
  }

  // ----- processes -----
  property Process loadProc: Process {
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector { onStreamFinished: root.load(text) }
  }
  property Process applyProc: Process {
    stdout: StdioCollector { onStreamFinished: root.applyDone(text) }
  }
  property Process restoreProc: Process {
    property bool quitAfter: false
    stdout: StdioCollector { onStreamFinished: restoreSettle.start() }
  }
  property Process watchdog: Process {}

  // ----- timers -----
  // Give the compositor a moment to finish reconfiguring before nudging.
  property Timer settleTimer: Timer {
    interval: 400
    onTriggered: { root.settled(); root.confirmShown(); }
  }
  property Timer restoreSettle: Timer {
    interval: 400
    onTriggered: { if (restoreProc.quitAfter) root.finish(); else root.settled(); }
  }
  property Timer quitTimer: Timer {
    interval: 400
    onTriggered: root.quitRequested()
  }
  property Timer spinTimer: Timer {
    interval: 80; repeat: true
    onTriggered: root.spin++
  }
  property Timer countdown: Timer {
    interval: 1000; repeat: true
    onTriggered: { if (root.left <= 1) root.revert(true); else root.left--; }
  }
}

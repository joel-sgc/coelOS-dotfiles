.pragma library

// Live-activity island: palette, motion tokens and "part" constructors.
//
// A row in the island is a list of groups; a group is a list of parts laid out
// 5 px apart (one chip), groups sit 8 px apart. Sources describe what they show
// with these plain objects and IslandPart.qml draws them, so a source never
// builds QML itself. Design source: example/Pill Board.dc.html (the `K` kit).

// One Dark, exactly the mockup's `C`.
const C = {
  bg: "#282c34", sf: "#404754", fg: "#abb2bf", mu: "#5c6370",
  red: "#ef596f", err: "#f44747", or: "#d19a66", ye: "#e5c07b",
  gr: "#89ca78", cy: "#2bbac5", bl: "#61afef", pu: "#d55fde",
};

// Motion tokens, verbatim from the board (easing.bezierCurve wants the
// trailing 1, 1). morph: shape size/position. exit: content out. enter: in.
const morph = [0.2, 0, 0, 1, 1, 1];
const exit = [0.4, 0, 1, 1, 1, 1];
const enter = [0, 0, 0.2, 1, 1, 1];

function icon(name, color, size, fill) {
  return { k: "icon", name: name, color: color || C.fg, size: size || 14, fill: !!fill };
}
// maxWidth > 0 elides; 0 = natural width.
function text(s, color, size, maxWidth) {
  return { k: "text", s: String(s), color: color || C.fg, size: size || 13, maxWidth: maxWidth || 0 };
}
function muted(s, size, maxWidth) { return text(s, C.mu, size, maxWidth); }
function ring(pct, color, size) { return { k: "ring", p: pct, color: color || C.cy, size: size || 14 }; }
function eq(color, on) { return { k: "eq", color: color || C.gr, on: on !== false }; }
function dot(color, size, blink) { return { k: "dot", color: color || C.fg, size: size || 7, blink: !!blink }; }
// A small camera frame, h tall; its width follows the camera's aspect (w is ignored).
// src "" draws the placeholder plate.
function thumb(w, h, src) { return { k: "thumb", w: w, h: h, src: src || "" }; }
function space(w) { return { k: "space", w: w }; }

// Each part its own group (glance / interrupt rows: 8 px between everything).
function spread(parts) { return parts.map(p => [p]); }

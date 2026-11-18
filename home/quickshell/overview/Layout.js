.pragma library

// What the workspace overview shows, as plain data (no Quickshell objects), so it
// can be tested: `node home/quickshell/overview/Layout.test.js`.
//
// Workspaces are a grid of ROWS rows of ROW columns (home/hyprland/grid.lua): row 0
// is workspaces 1..100, row 1 is 101..200, up to row 4. Every row is shown as a
// strip of small desktops: the workspaces in it that have windows, plus the one
// you would be taken back to (its "representative", which may be empty).

var ROW = 100;
var ROWS = 5;

// A readable name for a window's class: "zen" -> "Zen Browser", "code" -> "VS Code",
// "chrome-cad.onshape.com__-Default" (a Chrome app window) -> "Onshape",
// "org.kde.dolphin" -> "Dolphin".
var KNOWN = {
  "zen": "Zen Browser", "zen-browser": "Zen Browser", "zen-alpha": "Zen Browser", "firefox": "Firefox",
  "code": "VS Code", "code-oss": "VS Code", "code-url-handler": "VS Code", "vscodium": "VSCodium",
  "google-chrome": "Chrome", "chromium": "Chromium", "brave-browser": "Brave",
  "kitty": "Kitty", "ghostty": "Ghostty", "com.mitchellh.ghostty": "Ghostty", "alacritty": "Alacritty",
  "org.kde.dolphin": "Files", "org.gnome.nautilus": "Files", "thunar": "Files",
  "org.pwmt.zathura": "Zathura", "mpv": "mpv", "obsidian": "Obsidian", "discord": "Discord",
  "signal": "Signal", "spotify": "Spotify", "steam": "Steam", "gimp": "GIMP", "vlc": "VLC",
  "org.kde.kate": "Kate", "org.kde.okular": "Okular", "org.kde.spectacle": "Spectacle",
  "slack": "Slack", "telegram-desktop": "Telegram", "org.telegram.desktop": "Telegram",
  "libreoffice-writer": "Writer", "libreoffice-calc": "Calc", "pavucontrol": "Volume",
};
function titleCase(w) { return w ? w.charAt(0).toUpperCase() + w.slice(1) : w; }
function appName(cls) {
  var c = String(cls || "").trim();
  if (!c) return "";
  var key = c.toLowerCase();
  if (KNOWN[key]) return KNOWN[key];
  // Chrome / Chromium app windows: chrome-<host>__<path>-<profile>
  var app = /^(?:chrome|chromium|brave|msedge)-([^_]+?)(?:__.*)?-(?:default|profile.*)$/i.exec(c);
  if (app) {
    var parts = app[1].split(".").filter(function (p) { return p; });
    if (parts.length > 1) parts.pop();                                   // the TLD
    if (parts.length > 1 && /^(co|com|org|net|ac)$/.test(parts[parts.length - 1])) parts.pop();
    return titleCase(parts[parts.length - 1] || app[1]);
  }
  // Reverse-DNS ids: keep the last part.
  if (c.indexOf(".") > 0 && /^[a-z]{2,}\.[A-Za-z0-9_.-]+$/i.test(c)) c = c.slice(c.lastIndexOf(".") + 1);
  return c.split(/[-_ ]+/).map(titleCase).join(" ");
}

function rowOf(id) { return Math.floor((id - 1) / ROW); }
function colOf(id) { return (id - 1) % ROW + 1; }          // 1-based, as on the bar
function idOf(row, col) { return row * ROW + col; }

// "1,,,307," (grid.lua's snapshot) -> [1, 0, 0, 307, 0]; anything unusable is 0.
function parseRemembered(text) {
  var out = [];
  var parts = String(text || "").trim().split(",");
  for (var i = 0; i < ROWS; i++) {
    var n = parseInt(parts[i], 10);
    out.push(n >= 1 && rowOf(n) === i ? n : 0);
  }
  return out;
}

// The rows file has a line per monitor, "<monitor name>:<five ids>": the ids of `name`.
function rememberedFor(fileText, name) {
  var lines = String(fileText || "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var at = lines[i].lastIndexOf(":");
    if (at > 0 && lines[i].slice(0, at) === name) return lines[i].slice(at + 1).trim();
  }
  return "";
}

// clients: `hyprctl -j clients`. opts:
//   monitorId, monX, monY  the monitor being shown; windows are placed relative to it
//   monitors               `hyprctl -j monitors`: windows that are on another monitor are fitted
//                          into this one's shape (same proportions, centred, nothing stretched)
//   focusedId              the workspace you are on (-1 / <= 0 when a scratchpad is up)
//   remembered             grid.lua's snapshot text, or an array from parseRemembered()
//
// Returns exactly ROWS rows: [{ index, label, current, desks: [desk] }],
// desk: { id, col, rep, windows: [{ address, cls, title, x, y, w, h, floating }] }.
// Windows are in screen pixels; tiled ones come before floating ones so floating
// windows are drawn on top.
function rowsOf(clients, opts) {
  opts = opts || {};
  var focusedId = opts.focusedId >= 1 ? opts.focusedId : -1;
  var remembered = Array.isArray(opts.remembered) ? opts.remembered : parseRemembered(opts.remembered);
  var mons = {};
  (opts.monitors || []).forEach(function (m) { mons[m.id] = m; });
  var target = mons[opts.monitorId];
  var monX = opts.monX || 0, monY = opts.monY || 0;

  var byWs = {};
  (clients || []).forEach(function (c) {
    if (!c || !c.workspace || c.workspace.id < 1) return;                // scratchpads
    if (c.mapped === false || c.hidden === true) return;
    var id = c.workspace.id;
    if (rowOf(id) >= ROWS) return;
    var at = c.at || [0, 0], size = c.size || [0, 0];
    var x = at[0] - monX, y = at[1] - monY, w = size[0] || 0, h = size[1] || 0;
    var from = mons[c.monitor];
    if (target && from && from.id !== target.id && from.width > 0 && from.height > 0) {
      // On another monitor: fit that monitor's screen into this one's, keeping proportions.
      var k = Math.min(target.width / from.width, target.height / from.height);
      x = (target.width - from.width * k) / 2 + (at[0] - from.x) * k;
      y = (target.height - from.height * k) / 2 + (at[1] - from.y) * k;
      w *= k; h *= k;
    }
    (byWs[id] = byWs[id] || []).push({
      address: c.address, cls: c.class || c.initialClass || "", name: appName(c.class || c.initialClass), title: c.title || "",
      x: x, y: y, w: Math.max(1, w), h: Math.max(1, h),
      floating: !!c.floating,
    });
  });
  Object.keys(byWs).forEach(function (id) {
    byWs[id].sort(function (a, b) { return (a.floating ? 1 : 0) - (b.floating ? 1 : 0); });
  });

  var focusedRow = focusedId >= 1 ? rowOf(focusedId) : -1;
  var rows = [];
  for (var r = 0; r < ROWS; r++) {
    var ids = Object.keys(byWs).map(Number).filter(function (id) { return rowOf(id) === r; });
    ids.sort(function (a, b) { return a - b; });

    var rep;
    if (r === focusedRow && rowOf(focusedId) < ROWS) rep = focusedId;
    else if (remembered[r] >= 1 && rowOf(remembered[r]) === r) rep = remembered[r];
    else if (ids.length) rep = ids[0];
    else rep = idOf(r, 1);
    // Every workspace from the row's start up to the last one in use (one with windows,
    // or the one the row returns to) is shown, so an empty workspace with something
    // after it never disappears. Then one more, empty, to open something in (unless
    // the last one is already empty).
    var lastUsed = Math.max(rep, ids.length ? ids[ids.length - 1] : 0);
    ids = [];
    for (var id = idOf(r, 1); id <= lastUsed; id++) ids.push(id);
    if ((byWs[lastUsed] || []).length && colOf(lastUsed) < ROW) ids.push(lastUsed + 1);

    rows.push({
      index: r, label: "r" + (r + 1), current: r === focusedRow,
      desks: ids.map(function (id) {
        return { id: id, col: colOf(id), rep: id === rep, windows: byWs[id] || [] };
      }),
    });
  }
  return rows;
}

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

// clients: `hyprctl -j clients`. opts:
//   monitorId, monX, monY  only windows on this monitor, positioned relative to it
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
  var monX = opts.monX || 0, monY = opts.monY || 0;

  var byWs = {};
  (clients || []).forEach(function (c) {
    if (!c || !c.workspace || c.workspace.id < 1) return;                // scratchpads
    if (c.mapped === false || c.hidden === true) return;
    if (opts.monitorId !== undefined && opts.monitorId !== null && opts.monitorId >= 0 && c.monitor !== opts.monitorId) return;
    var id = c.workspace.id;
    if (rowOf(id) >= ROWS) return;
    var at = c.at || [0, 0], size = c.size || [0, 0];
    (byWs[id] = byWs[id] || []).push({
      address: c.address, cls: c.class || c.initialClass || "", name: appName(c.class || c.initialClass), title: c.title || "",
      x: at[0] - monX, y: at[1] - monY, w: Math.max(1, size[0] || 0), h: Math.max(1, size[1] || 0),
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
    if (ids.indexOf(rep) < 0) { ids.push(rep); ids.sort(function (a, b) { return a - b; }); }
    // A row always ends in an empty workspace to open something in: when its last
    // one has windows, offer the next. (An empty one is left as it is.)
    var last = ids[ids.length - 1];
    if ((byWs[last] || []).length && colOf(last) < ROW) ids.push(last + 1);

    rows.push({
      index: r, label: "r" + (r + 1), current: r === focusedRow,
      desks: ids.map(function (id) {
        return { id: id, col: colOf(id), rep: id === rep, windows: byWs[id] || [] };
      }),
    });
  }
  return rows;
}

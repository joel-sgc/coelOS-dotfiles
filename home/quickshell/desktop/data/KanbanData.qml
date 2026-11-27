pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../../widgets"

// The kanban board: three columns (todo / doing / done) in kanban.json
// (hand-editable; edits made while running are picked up).
// Cards: { id, title, notes, tag, high, due("YYYY-MM-DD"), pomos }.
// Title text understands "!high", "#tag" and "@today|tomorrow|fri|2026-10-20".
// Every kanban card on the desktop (any size, any monitor) edits this one copy.
Singleton {
  id: kb

  property var columns: defaultColumns()
  property int nextId: 1
  property bool loaded: false
  property bool saveBlocked: false
  property string lastSaved: ""

  // The editor (KanbanEditor.qml) is hosted by the main screen's desktop.
  signal editRequested(var card, string rawTitle, int col)
  signal newRequested(int col)

  function defaultColumns() {
    return [
      { id: "todo", title: "todo", cards: [] },
      { id: "doing", title: "doing", cards: [] },
      { id: "done", title: "done", cards: [] }
    ];
  }
  readonly property int total: {
    let n = 0;
    for (const c of columns) n += c.cards.length;
    return n;
  }
  readonly property int doneCount: columns.length > 2 ? columns[2].cards.length : 0
  readonly property int doingCount: columns.length > 1 ? columns[1].cards.length : 0
  readonly property int donePct: total ? Math.round(doneCount / total * 100) : 0

  function clone(v) { return JSON.parse(JSON.stringify(v)); }
  function find(cols, cardId) {
    for (let c = 0; c < cols.length; c++)
      for (let i = 0; i < cols[c].cards.length; i++)
        if (cols[c].cards[i].id === cardId) return { col: c, idx: i };
    return null;
  }
  // Cards of a column, optionally only those tagged `tag` (case-insensitive).
  function cardsOf(col, tag) {
    const list = columns[col] ? columns[col].cards : [];
    if (!tag) return list;
    const t = String(tag).toLowerCase();
    return list.filter(c => String(c.tag || "").toLowerCase() === t);
  }

  // ----- title syntax -----
  function dkey(d) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }
  function parseDue(v) {
    v = v.toLowerCase();
    const now = new Date();
    const at = n => dkey(new Date(now.getFullYear(), now.getMonth(), now.getDate() + n));
    if (v === "today") return at(0);
    if (v === "tom" || v === "tomorrow") return at(1);
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
    const i = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].indexOf(v.slice(0, 3));
    if (i >= 0) return at(((i - now.getDay()) + 7) % 7 || 7);
    return "";
  }
  function parseTitle(raw) {
    let high = false, tag = "", due = "", m;
    if ((m = raw.match(/(^|\s)!high\b/))) { high = true; raw = raw.replace(m[0], " "); }
    if ((m = raw.match(/(^|\s)#(\S+)/))) { tag = m[2]; raw = raw.replace(m[0], " "); }
    if ((m = raw.match(/(^|\s)@(\S+)/))) {
      const d = parseDue(m[2]);
      if (d) { due = d; raw = raw.replace(m[0], " "); }
    }
    return { title: raw.replace(/\s+/g, " ").trim(), high: high, tag: tag, due: due };
  }
  function composeTitle(c) {
    return c.title + (c.high ? " !high" : "") + (c.tag ? " #" + c.tag : "") + (c.due ? " @" + c.due : "");
  }
  // "today" (red) / "tomorrow" / "fri" / "dec 4" (overdue: red)
  function dueInfo(due) {
    if (!due) return null;
    const d = new Date(due + "T12:00:00");
    const now = new Date();
    const diff = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 864e5);
    if (diff === 0) return { text: "today", color: Pal.red, days: 0 };
    if (diff === 1) return { text: "tomorrow", color: Pal.orange, days: 1 };
    if (diff < 0) return { text: Qt.formatDate(d, "MMM d").toLowerCase(), color: Pal.red, days: diff };
    if (diff < 7) return { text: Qt.formatDate(d, "ddd").toLowerCase(), color: Pal.muted, days: diff };
    return { text: Qt.formatDate(d, "MMM d").toLowerCase(), color: Pal.muted, days: diff };
  }

  // ----- persistence -----
  function save() {
    if (!loaded || saveBlocked) return;
    const text = JSON.stringify({ nextId: nextId, columns: columns }, null, 2);
    lastSaved = text;
    file.setText(text);
  }
  function applyText(text) {
    let j;
    try { j = JSON.parse(text); } catch (e) {
      console.warn("kanban: kanban.json is not valid JSON, leaving it untouched:", e);
      saveBlocked = true;
      return;
    }
    if (!j || !Array.isArray(j.columns) || j.columns.length !== 3) {
      console.warn("kanban: kanban.json needs exactly 3 columns, leaving it untouched");
      saveBlocked = true;
      return;
    }
    saveBlocked = false;
    columns = j.columns;
    nextId = j.nextId || 1;
    loaded = true;
  }
  readonly property string dataDir: Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")
  property bool dirReady: false
  Process {
    running: true
    command: ["mkdir", "-p", kb.dataDir]
    onExited: kb.dirReady = true
  }
  FileView {
    id: file
    path: kb.dirReady ? kb.dataDir + "/kanban.json" : ""
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      const t = text();
      if (t === kb.lastSaved) return;   // our own write echoing back
      kb.applyText(t);
    }
    onLoadFailed: if (!kb.loaded) { kb.loaded = true; kb.save(); }
  }

  // ----- mutations -----
  function addCard(col, p, notes) {
    const cols = clone(columns);
    const id = nextId;
    cols[col].cards.push({ id: id, title: p.title, notes: notes, tag: p.tag, high: p.high, due: p.due });
    nextId += 1;
    columns = cols;
    save();
    return id;
  }
  function updateCard(cardId, p, notes, col) {
    const cols = clone(columns);
    const at = find(cols, cardId);
    if (!at) return;
    const card = cols[at.col].cards.splice(at.idx, 1)[0];
    card.title = p.title; card.notes = notes; card.tag = p.tag; card.high = p.high; card.due = p.due;
    if (col === at.col) cols[col].cards.splice(at.idx, 0, card);
    else cols[col].cards.push(card);
    columns = cols;
    save();
  }
  function deleteCard(cardId) {
    const cols = clone(columns);
    const at = find(cols, cardId);
    if (!at) return;
    cols[at.col].cards.splice(at.idx, 1);
    columns = cols;
    save();
  }
  function moveCard(cardId, toCol, toIdx) {
    const cols = clone(columns);
    const at = find(cols, cardId);
    if (!at) return;
    const card = cols[at.col].cards.splice(at.idx, 1)[0];
    if (at.col === toCol && at.idx < toIdx) toIdx -= 1;
    cols[toCol].cards.splice(Math.max(0, Math.min(toIdx, cols[toCol].cards.length)), 0, card);
    columns = cols;
    save();
  }
  // todo -> doing -> done -> back to todo
  function advance(cardId) {
    const at = find(columns, cardId);
    if (at) moveCard(cardId, at.col === 2 ? 0 : at.col + 1, 1e9);
  }
  // Set the due date ("YYYY-MM-DD") of several cards at once (wind-down's `>`).
  function setDue(ids, due) {
    const cols = clone(columns);
    for (const id of ids) {
      const at = find(cols, id);
      if (at) cols[at.col].cards[at.idx].due = due;
    }
    columns = cols;
    save();
  }
  // A finished Pomodoro on this card.
  function bumpPomos(cardId) {
    const cols = clone(columns);
    const at = find(cols, cardId);
    if (!at) return;
    const c = cols[at.col].cards[at.idx];
    c.pomos = (c.pomos || 0) + 1;
    columns = cols;
    save();
  }
  function openNew(col) { newRequested(col); }
  function openEdit(card) {
    const at = find(columns, card.id);
    if (at) editRequested(card, composeTitle(card), at.col);
  }
}

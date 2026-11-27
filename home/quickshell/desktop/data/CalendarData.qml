pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../../widgets"

// Calendar events for the desktop: hand-written events.json plus what
// coel-gcal-sync writes to gcal-events.json, both {date, start, end, title,
// where, cal}. Event colors (colorOf) are shared with the panel's calendar
// dropdown.
Singleton {
  id: root

  // An event's color: per feed (`cal`, the gcal-url label), except classes,
  // which get one color per title, since every meeting of a class repeats it.
  // Repeating class titles take classPalette in order of how often they occur
  // (ties by title), so the main classes keep distinct, stable colors; one-off
  // class entries share orange. Yellow is left out: it's the google feed's.
  readonly property var calColors: ({ work: Pal.blue, personal: Pal.purple, health: Pal.green, google: Pal.yellow, "class": Pal.red })
  readonly property var classPalette: [Pal.red, Pal.blue, Pal.green, Pal.purple, Pal.cyan, Pal.orange]
  function titleKey(t) { return String(t || "").trim().toLowerCase(); }
  readonly property var classColors: {
    const n = {};
    for (const e of all) if (e.cal === "class") { const k = titleKey(e.title); n[k] = (n[k] || 0) + 1; }
    const repeating = Object.keys(n).filter(k => n[k] > 1).sort((a, b) => n[b] - n[a] || a.localeCompare(b));
    const out = {};
    repeating.forEach((k, i) => out[k] = classPalette[i % classPalette.length]);
    return out;
  }
  function colorOf(e) {
    if (!e) return Pal.blue;
    if (e.cal === "class") return classColors[titleKey(e.title)] || Pal.orange;
    return calColors[e.cal] || Pal.blue;
  }

  property var events: []
  property var gcalEvents: []
  readonly property var all: events.concat(gcalEvents)
  readonly property var byDay: {
    const m = {};
    for (const e of all) (m[e.date] = m[e.date] || []).push(e);
    for (const k in m) m[k].sort((a, b) => (a.start || "").localeCompare(b.start || ""));
    return m;
  }

  property real nowMs: Date.now()
  Timer { interval: 60000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }

  function dkey(d) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }
  function isoWeek(d) {
    const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
    const dn = t.getUTCDay() || 7;
    t.setUTCDate(t.getUTCDate() + 4 - dn);
    const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
    return Math.ceil(((t - y0) / 864e5 + 1) / 7);
  }
  readonly property string todayKey: dkey(new Date(nowMs))
  readonly property var today: byDay[todayKey] || []

  // ----- the selected day, shared by the calendar and next-up cards -----
  // Days from today. Moving on either card moves both; it drifts back to today
  // after 5 min untouched, so the desktop always comes back to "now".
  property int selOffset: 0
  readonly property var selDate: { const n = new Date(nowMs); return new Date(n.getFullYear(), n.getMonth(), n.getDate() + selOffset); }
  readonly property string selKey: dkey(selDate)
  readonly property var selEvents: byDay[selKey] || []
  readonly property bool viewingToday: selOffset === 0
  // "today" / "tomorrow" / "yesterday" / "thursday, dec 4"
  readonly property string selLabel: selOffset === 0 ? "today" : selOffset === 1 ? "tomorrow" : selOffset === -1 ? "yesterday"
    : Qt.formatDate(selDate, "dddd, MMM d").toLowerCase()
  function shift(n) { selOffset += n; backToToday.restart(); }
  function goToday() { selOffset = 0; backToToday.stop(); }
  function select(key) {
    const p = key.split("-").map(Number), n = new Date(nowMs);
    shift(Math.round((new Date(p[0], p[1] - 1, p[2]) - new Date(n.getFullYear(), n.getMonth(), n.getDate())) / 864e5) - selOffset);
  }
  Timer { id: backToToday; interval: 5 * 60000; onTriggered: root.selOffset = 0 }
  // Keys shared by both cards: h/l (←/→) day, [ ] week, t today.
  function handleDayKey(e) {
    if (e.text === "h" || e.key === Qt.Key_Left) shift(-1);
    else if (e.text === "l" || e.key === Qt.Key_Right) shift(1);
    else if (e.key === Qt.Key_BracketLeft) shift(-7);
    else if (e.key === Qt.Key_BracketRight) shift(7);
    else if (e.text === "t") goToday();
    else return false;
    return true;
  }

  readonly property int week: isoWeek(selDate)
  // Monday-first, the selected day's week: {key, dow, day, isToday, isSel, colors}
  readonly property var weekDays: {
    const n = selDate, dow = (n.getDay() + 6) % 7, out = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(n.getFullYear(), n.getMonth(), n.getDate() - dow + i), k = dkey(d);
      const cols = [];
      for (const e of (byDay[k] || [])) { const c = String(colorOf(e)); if (cols.indexOf(c) < 0) cols.push(c); }
      out.push({ key: k, dow: ["mo", "tu", "we", "th", "fr", "sa", "su"][i], day: d.getDate(),
                 isToday: k === todayKey, isSel: k === selKey, colors: cols.slice(0, 4) });
    }
    return out;
  }
  // The next timed event still to come today, for a minimized card.
  readonly property string summary: {
    const n = new Date(nowMs), hm = String(n.getHours()).padStart(2, "0") + ":" + String(n.getMinutes()).padStart(2, "0");
    const next = today.filter(e => (e.start || "") > hm);
    return next.length ? next[0].start + " " + next[0].title : "nothing left today";
  }

  function loadInto(prop, text) {
    try { const j = JSON.parse(text); root[prop] = Array.isArray(j) ? j : []; }
    catch (e) { console.warn("calendar: bad JSON in", prop, e); root[prop] = []; }
  }
  readonly property string dataDir: Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")
  FileView {
    path: root.dataDir + "/gcal-events.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.loadInto("gcalEvents", text())
    onLoadFailed: root.gcalEvents = []
  }
  FileView {
    path: root.dataDir + "/events.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.loadInto("events", text())
    onLoadFailed: root.events = []
  }
}

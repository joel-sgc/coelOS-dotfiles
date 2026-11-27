pragma Singleton
import QtQuick
import Quickshell
import "../../widgets"
import "../../modes"
import "../../services"

// What's next, for the desktop's next-up card: calendar events merged with due
// dates. The unlabelled gcal feed (`cal: "google"`) is the school's LMS, whose
// entries are deadlines dressed as 30-min events, so they count as due items,
// never as events (no countdown, not on the timeline). Kanban due dates are due
// items too. Flavors (Desktop Board): morning (countdown + today), class (the
// class you're in), wind-down (tomorrow first thing), free day (nothing today).
Singleton {
  id: nd

  readonly property var deadlineCals: ["google"]

  readonly property real now: CalendarData.nowMs
  function at(date, hm) {
    const d = date.split("-").map(Number), t = (hm || "00:00").split(":").map(Number);
    return new Date(d[0], d[1] - 1, d[2], t[0], t[1]).getTime();
  }
  function hhmm(ms) { return Qt.formatDateTime(new Date(ms), "hh:mm"); }
  function dayStart(ms) { const d = new Date(ms); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }
  function daysFrom(ms) { return Math.round((dayStart(ms) - dayStart(now)) / 864e5); }
  // "today" / "tomorrow" / "fri" / "dec 4"
  function dayWord(ms) {
    const n = daysFrom(ms);
    if (n === 0) return "today";
    if (n === 1) return "tomorrow";
    if (n > 1 && n < 7) return Qt.formatDate(new Date(ms), "ddd").toLowerCase();
    return Qt.formatDate(new Date(ms), "MMM d").toLowerCase();
  }
  function dayColor(ms) {
    const n = daysFrom(ms);
    return n <= 0 ? Pal.red : n === 1 ? Pal.orange : n < 4 ? Pal.yellow : Pal.muted;
  }

  // ---- events (timed, not deadlines) ----
  readonly property var events: CalendarData.all
    .filter(e => e.start && e.end && deadlineCals.indexOf(e.cal) < 0)
    .map(e => ({ title: e.title, where: e.where || "", cal: e.cal, start: at(e.date, e.start), end: at(e.date, e.end),
                 isClass: e.cal === "class", color: CalendarData.colorOf(e) }))
    .sort((a, b) => a.start - b.start)
  readonly property var today: events.filter(e => daysFrom(e.start) === 0)
  readonly property bool free: today.length === 0
  readonly property var current: events.find(e => e.start <= now && now < e.end) || null
  readonly property var next: events.find(e => e.start > now) || null
  // Before 04:00 the night isn't over yet: "tomorrow" is still later today.
  readonly property bool lateNight: new Date(now).getHours() < 4
  readonly property var tomorrowFirst: lateNight ? (events.find(e => daysFrom(e.start) === 0 && e.start > now) || null)
                                                 : (events.find(e => daysFrom(e.start) === 1) || null)
  readonly property var later: events.filter(e => e.start > now && (!current || e.start >= current.end))

  // ---- due items: LMS deadlines + kanban due dates, not done ----
  readonly property var dues: {
    const out = [];
    for (const e of CalendarData.all) {
      if (deadlineCals.indexOf(e.cal) < 0) continue;
      const t = at(e.date, e.start || "23:59");
      if (t < now - 3600000 || daysFrom(t) > 14) continue;
      out.push({ title: e.title, at: t, timed: !!e.start, kind: "lms" });
    }
    for (let c = 0; c < 2; c++) for (const k of KanbanData.cardsOf(c)) {
      if (!k.due) continue;
      const t = at(k.due, "23:59");
      if (daysFrom(t) > 14) continue;
      out.push({ title: k.title, at: t, timed: false, kind: "kanban", tag: k.tag || "", id: k.id });
    }
    return out.sort((a, b) => a.at - b.at);
  }
  readonly property int dueToday: dues.filter(d => daysFrom(d.at) <= 0).length

  // ---- rows (Desktop Board `upRows`): {when, whenColor, icon, iconColor, title, meta, tag} ----
  function eventRow(e) {
    const d = daysFrom(e.start);
    return { when: d === 0 ? hhmm(e.start) : dayWord(e.start), whenColor: e.color,
             icon: e.isClass ? "chalkboard-teacher" : "calendar-blank", iconColor: e.color,
             title: e.title, meta: e.where, tag: "" };
  }
  function dueRow(d) {
    const c = dayColor(d.at);
    return { when: d.timed && daysFrom(d.at) === 0 ? hhmm(d.at) : dayWord(d.at), whenColor: c,
             icon: d.kind === "lms" ? "graduation-cap" : "kanban", iconColor: c,
             title: d.title, meta: d.timed && daysFrom(d.at) !== 0 ? hhmm(d.at) : "", tag: d.tag || "" };
  }
  // Today's remaining events and what's due soon, in time order.
  readonly property var comingUp: {
    const rows = later.filter(e => daysFrom(e.start) === 0).map(e => ({ t: e.start, r: eventRow(e) }))
      .concat(dues.filter(d => daysFrom(d.at) <= 2).map(d => ({ t: d.at, r: dueRow(d) })));
    return rows.sort((a, b) => a.t - b.t).map(x => x.r);
  }
  readonly property var afterClass: {
    if (!current) return [];
    const rows = later.filter(e => daysFrom(e.start) === 0).map(e => ({ t: e.start, r: eventRow(e) }))
      .concat(dues.filter(d => daysFrom(d.at) <= 1).map(d => ({ t: d.at, r: dueRow(d) })));
    return rows.sort((a, b) => a.t - b.t).map(x => x.r);
  }
  readonly property var dueSoon: {
    const rows = dues.map(dueRow);
    if (next) rows.push(Object.assign(eventRow(next), { meta: hhmm(next.start) + " · first event" }));
    return rows.slice(0, 5);
  }

  // ---- countdowns ----
  function untilText(ms) {
    const m = Math.max(0, Math.round((ms - now) / 60000));
    if (m < 60) return { n: String(m), unit: " min" };
    const h = Math.round(m / 60);
    return h < 48 ? { n: String(h), unit: " h" } : { n: String(Math.round(h / 24)), unit: " days" };
  }
  readonly property var untilNext: next ? untilText(next.start) : ({ n: "", unit: "" })
  readonly property int classLeftMin: current ? Math.max(0, Math.round((current.end - now) / 60000)) : 0
  readonly property real classProgress: current ? Math.min(100, (now - current.start) / (current.end - current.start) * 100) : 0

  // ---- wind-down ----
  readonly property var leftOpen: {
    const out = KanbanData.cardsOf(1).map(c => ({ c: c, col: 1 }));
    for (const c of KanbanData.cardsOf(0))
      if (c.due && daysFrom(at(c.due, "12:00")) <= 0) out.push({ c: c, col: 0 });
    return out;
  }
  // `>`: everything left open is due tomorrow.
  function moveOpenToTomorrow() {
    const d = new Date(now + 864e5);
    const key = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    KanbanData.setDue(leftOpen.map(x => x.c.id), key);
  }
  readonly property int todayDone: today.filter(e => e.end <= now).length
  readonly property string todayLine: {
    const parts = lateNight ? [] : [todayDone + " of " + today.length + (today.length === 1 ? " event" : " events")];
    if ((Printer.status === "finished" || Printer.status === "failed") && Printer.endedAt && daysFrom(Printer.endedAt) === 0)
      parts.push((Printer.status === "finished" ? "printed " : "print failed: ") + Printer.shortFile);
    parts.push(KanbanData.doneCount + " done on the kanban");
    return parts.join(" · ");
  }

  // ----- any day (the calendar's selected day) -----
  function keyOf(ms) { return CalendarData.dkey(new Date(ms)); }
  function eventsOn(key) { return events.filter(e => keyOf(e.start) === key); }
  function duesOn(key) { return dues.filter(d => keyOf(d.at) === key); }
  // Events and due items of that day, in time order, as rows.
  function rowsOn(key) {
    return eventsOn(key).map(e => ({ t: e.start, r: Object.assign(eventRow(e), { when: hhmm(e.start) }) }))
      .concat(duesOn(key).map(d => ({ t: d.at, r: Object.assign(dueRow(d), { when: d.timed ? hhmm(d.at) : "due" }) })))
      .sort((a, b) => a.t - b.t).map(x => x.r);
  }

  // One line for a minimized card, per flavor.
  function summaryFor(flavor) {
    if (flavor === "class" && current) return current.title + " · " + classLeftMin + "m left";
    if (flavor === "winddown") return tomorrowFirst ? "tomorrow " + hhmm(tomorrowFirst.start) + " · " + leftOpen.length + " left open"
      : leftOpen.length + " left open";
    if (free) return "free day" + (next ? " · next " + dayWord(next.start) + " " + hhmm(next.start) : "");
    return next ? "in " + untilNext.n + untilNext.unit.trim() + " · " + next.title : "nothing else today";
  }
}

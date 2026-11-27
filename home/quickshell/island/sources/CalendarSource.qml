import QtQuick
import Quickshell
import "../../desktop/data"
import "../Parts.js" as P

// The calendar on the pill (Pill Board "Calendar"): the warm-up before events
// (Class mode switches on at the start, so the countdown lives here).
//   15 min before   ambient: calendar glyph + minutes left
//   10 and 2 min    glance "Robotics in 10 min · room"
//   class starts    interrupt "Robotics starts now" (silent), until dismissed,
//                   snoozed, or 10 min into it
//   card            today's next events
// Events only: LMS deadlines (NextData) never count down here.
Scope {
  id: src
  property var engine
  readonly property var nd: NextData

  property real now: Date.now()
  Timer { interval: 15000; repeat: true; running: true; onTriggered: { src.now = Date.now(); src.tick(); } }

  readonly property var soon: {
    const e = nd.next;
    return e && e.start - now <= 15 * 60000 && e.start > now ? e : null;
  }
  readonly property int minsLeft: soon ? Math.max(1, Math.ceil((soon.start - now) / 60000)) : 0

  readonly property var chips: !soon ? [] : [{
    id: "calendar", deskCard: "next", source: src, prio: 30, card: cardComp,
    parts: [[P.icon(soon.isClass ? "chalkboard-teacher" : "calendar-blank", P.C.ye, 13), P.text(minsLeft + "m", P.C.ye, 12)]],
    label: soon.title, value: "in " + minsLeft + "m", valueColor: P.C.ye
  }]

  Component { id: cardComp; CalendarIslandCard {} }
  Component { id: nowDrop; ClassNowDrop {} }

  // Which warnings went out, per event ("start|title" -> {g10, g2, now}).
  property var sent: ({})
  property var snoozedUntil: ({})
  function key(e) { return e.start + "|" + e.title; }
  function mark(k, what) { const s = Object.assign({}, sent); s[k] = Object.assign({}, s[k] || {}); s[k][what] = true; sent = s; }

  function tick() {
    const e = nd.next, cur = nd.current;
    if (e) {
      const k = key(e), left = (e.start - now) / 60000, s = sent[k] || {};
      for (const [at, tag] of [[10, "g10"], [2, "g2"]]) {
        if (left <= at && left > at - 1.5 && !s[tag]) {
          mark(k, tag);
          engine.glance({ id: "cal-countdown", cardId: "next", source: src, ms: 4000, accent: P.C.ye,
            parts: [P.icon("calendar-blank", P.C.ye, 14), P.text(e.title + " in " + Math.max(1, Math.round(left)) + " min"),
                    P.muted(e.where ? "· " + e.where : "", 13, 260)] });
        }
      }
    }
    // A class that just started interrupts until dismissed or 10 min in.
    if (cur && cur.isClass) {
      const k = key(cur), s = sent[k] || {}, inMin = (now - cur.start) / 60000;
      const snoozed = snoozedUntil[k] && now < snoozedUntil[k];
      if (inMin < 10 && !s.now && !snoozed) {
        mark(k, "now");
        engine.interrupt({ id: "class-now", source: src, accent: P.C.ye, drop: nowDrop, event: cur,
          parts: [P.icon("chalkboard-teacher", P.C.ye, 14, true), P.text(cur.title + " starts now", P.C.ye),
                  P.muted(cur.where ? "· " + cur.where : "", 13, 260)] });
      }
      if (inMin >= 10) engine.withdraw("class-now");
    }
  }
  function dismiss() { engine.dismissInterrupt("class-now"); }
  function snooze(e) {
    const k = key(e), s = Object.assign({}, snoozedUntil), d = Object.assign({}, sent);
    s[k] = Date.now() + 5 * 60000;
    if (d[k]) { d[k] = Object.assign({}, d[k]); delete d[k].now; }
    snoozedUntil = s; sent = d;
    engine.dismissInterrupt("class-now");
  }
  Component.onCompleted: tick()
}

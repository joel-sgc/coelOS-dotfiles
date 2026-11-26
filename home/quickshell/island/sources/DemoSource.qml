import QtQuick
import Quickshell
import "../Parts.js" as P

// Mock-only chips for judging the island with several activities at once
// (`island demo music|music-change|cal|rec|clear`). Delete once the real Mpris /
// calendar / recording sources exist.
Scope {
  id: src
  property var engine
  property bool music: false
  property bool cal: false
  property bool rec: false
  property real recT0: 0
  property real now: Date.now()

  Timer { interval: 1000; repeat: true; running: src.rec; onTriggered: src.now = Date.now() }

  function mmss(ms) {
    const t = Math.max(0, Math.floor(ms / 1000));
    return String(Math.floor(t / 60)).padStart(2, "0") + ":" + String(t % 60).padStart(2, "0");
  }

  readonly property var chips: {
    const out = [];
    if (rec) out.push({ id: "rec", source: src, prio: 10, card: null,
      parts: [[P.dot(P.C.red, 7, true), P.text(mmss(now - recT0), P.C.red, 12)]],
      label: "Recording", value: mmss(now - recT0), valueColor: P.C.red });
    if (cal) out.push({ id: "cal", source: src, prio: 30, card: null,
      parts: [[P.icon("calendar-blank", P.C.ye, 13), P.text("12m", P.C.ye, 12)]],
      label: "Robotics", value: "in 12m", valueColor: P.C.ye });
    if (music) out.push({ id: "music", source: src, prio: 70, card: null,
      parts: [[P.eq(P.C.gr, true)]], label: "Glue — Bicep", value: "2:41", valueColor: P.C.gr });
    return out;
  }

  function demo(what) {
    if (what === "music") music = !music;
    else if (what === "music-change") {
      music = true;
      engine.glance({ id: "music-change", source: src, ms: 3000, accent: P.C.gr,
        parts: [P.icon("music-notes", P.C.gr, 14), P.text("Glue"), P.muted("Bicep"), P.eq(P.C.gr, true)] });
    }
    else if (what === "cal") cal = !cal;
    else if (what === "rec") { rec = !rec; recT0 = Date.now(); now = recT0; }
    else { music = false; cal = false; rec = false; }
  }
}

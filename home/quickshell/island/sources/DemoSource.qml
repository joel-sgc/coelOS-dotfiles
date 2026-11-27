import QtQuick
import Quickshell
import "../Parts.js" as P

// Mock recording chip (`island demo rec|clear-demo`). Music and calendar have
// real sources now; delete this once screen recording has one.
Scope {
  id: src
  property var engine
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
    return out;
  }

  function demo(what) {
    if (what === "rec") { rec = !rec; recT0 = Date.now(); now = recT0; }
    else rec = false;
  }
}

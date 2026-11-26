import QtQuick
import Quickshell
import "../Parts.js" as P

// super+A (scripts/coel-ask-screen.sh), driven by Panel.qml's "assistant"
// IpcHandler: working() -> done(preview) | fail(message) | clear() (re-press = cancel).
//
//   working   ambient: sparkle, "reading screen", live elapsed; sweep under the island
//   done      glance 6 s: the answer (the script already copied it), then
//             an "answer ready" dot for 5 min; clicking it shows the answer again
//   fail      glance 4 s
//   clear     while working: a 1.2 s "cancelled" glance
// The card / follow-up / history / discreet mode from the board are not built yet.
Scope {
  id: src
  property var engine

  // idle | working | ready
  property string phase: "idle"
  property string answer: ""
  property real t0: 0
  property real took: 0
  property real now: Date.now()

  Timer {
    interval: 100
    repeat: true
    running: src.phase === "working"
    onTriggered: src.now = Date.now()
  }
  // "answer ready" lasts 5 min; the same cap covers a script that died mid-run.
  Timer {
    interval: 300000
    running: src.phase !== "idle"
    onTriggered: src.phase = "idle"
  }

  readonly property var chips: {
    if (phase === "working")
      return [{ id: "assistant", source: src, prio: 40, sweep: true, card: null,
                parts: [[P.icon("sparkle", P.C.pu, 13, true), P.text("reading screen", P.C.fg, 12),
                         P.muted(((now - t0) / 1000).toFixed(1) + "s", 12)]],
                label: "Assistant", value: "reading screen", valueColor: P.C.pu }];
    if (phase === "ready")
      return [{ id: "assistant", source: src, prio: 40, card: null,
                parts: [[P.icon("sparkle", P.C.pu, 13, true), P.dot(P.C.pu, 5)]],
                label: answer, value: "answer", valueColor: P.C.pu,
                activate: () => showAnswer() }];
    return [];
  }

  function showAnswer() {
    engine.glance({
      id: "ai-result", source: src, ms: 6000, accent: P.C.pu,
      parts: [P.icon("sparkle", P.C.pu, 13, true), P.text(answer, P.C.fg, 13, 620),
              P.muted(took.toFixed(1) + "s"), P.icon("check", P.C.gr, 12), P.text("copied", P.C.gr, 12)]
    });
  }

  function working() {
    engine.withdraw("ai-result");
    t0 = Date.now();
    now = t0;
    phase = "working";
  }
  function done(preview) {
    took = (Date.now() - (t0 || Date.now())) / 1000;
    answer = preview;
    phase = "ready";
    showAnswer();
  }
  function fail(message) {
    phase = "idle";
    engine.glance({
      id: "ai-result", source: src, ms: 4000,
      parts: [P.icon("sparkle", P.C.mu, 13, true), P.muted("no answer"), P.muted("· " + message, 13, 520)]
    });
  }
  function clear() {
    if (phase === "working")
      engine.glance({ id: "ai-result", source: src, ms: 1200,
                      parts: [P.icon("sparkle", P.C.mu, 13, true), P.muted("cancelled")] });
    phase = "idle";
  }
}

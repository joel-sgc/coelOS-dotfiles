import QtQuick
import Quickshell
import "../../services"
import "../Parts.js" as P

// The printer on the pill. Data and the daemon live in services/Printer.qml
// (shared with the desktop's printer card); this only maps them to chips and
// reacts to its signals.
//
//   heating           ambient: thermometer, orange
//   printing          ambient: progress ring + %                (card on hover)
//   paused            ambient: pause glyph + %, orange (red if the printer paused itself)
//   unreachable       ambient: grey ring + offline glyph, while a print was running
//   paused + fault    interrupt "Print failed" (resume / cancel / dismiss)
//   failed            interrupt (dismiss)
//   finished          glance 4 s with the camera frame
Scope {
  id: src
  property var engine
  readonly property var pr: Printer

  readonly property var chips: {
    if (!pr.active) return [];
    const base = { id: "printer", deskCard: "printer", source: pr, prio: 50, card: cardComp, label: pr.shortFile };
    if (pr.stale)
      return [Object.assign(base, { parts: [[P.ring(pr.pct, P.C.mu), P.text(pr.pct + "%", P.C.mu, 12),
        P.icon("wifi-slash", P.C.mu, 11)]], value: "offline · seen " + pr.hhmm(pr.lastSeen), valueColor: P.C.mu })];
    if (pr.status === "heating")
      return [Object.assign(base, { parts: [[P.icon("thermometer", P.C.or, 12), P.text("heating", P.C.or, 12)]],
        value: Math.round(pr.nozzle) + "/" + Math.round(pr.nozzleTarget) + "°", valueColor: P.C.or })];
    if (pr.status === "printing")
      return [Object.assign(base, { parts: [[P.ring(pr.pct, P.C.cy), P.text(pr.pct + "%", P.C.fg, 12)]],
        value: pr.pct + "% · " + pr.fmtDur(pr.remainingMin), valueColor: P.C.cy })];
    const c = pr.fault ? P.C.err : P.C.or;
    return [Object.assign(base, { parts: [[P.icon("pause", c, 11, true), P.text(pr.pct + "%", c, 12)]],
      value: "paused · " + pr.pct + "%", valueColor: c })];
  }

  Component { id: cardComp; PrinterCard {} }
  Component { id: failDrop; PrinterFailedDrop {} }

  Connections {
    target: Printer
    function onAlarmChanged(on) {
      if (!on) { src.engine.withdraw("print-failed"); return; }
      src.engine.interrupt({
        id: "print-failed", source: Printer, accent: P.C.err, drop: failDrop,
        parts: [P.icon("warning-octagon", P.C.err, 14, true), P.text("Print failed", P.C.err),
                P.muted("· layer " + Printer.layer + "/" + Printer.totalLayers)]
      });
    }
    function onFinished() {
      src.engine.glance({
        id: "print-done", cardId: "printer", source: Printer, ms: 4000,
        parts: [P.thumb(26, 18, Printer.snapshot), P.text("Print finished"),
                P.muted("· " + Printer.shortFile + (Printer.elapsedText ? " · " + Printer.elapsedText : "")),
                P.icon("check", P.C.gr, 13)]
      });
    }
    function onCommandFailed(cmd, error) {
      src.engine.glance({ id: "printer-cmd", source: Printer, ms: 4000,
        parts: [P.icon("printer", P.C.mu, 14), P.text("Couldn't " + cmd), P.muted("· " + error)] });
    }
  }

  // Kept for Panel.qml's `island demo` IPC.
  function demo(what) { Printer.demo(what); }
}

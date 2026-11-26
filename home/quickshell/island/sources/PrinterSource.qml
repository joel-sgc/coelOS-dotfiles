import QtQuick
import Quickshell
import Quickshell.Io
import "../Parts.js" as P

// Bambu P1S, via ../../scripts/coel-bambu.py (LAN MQTT + camera; credentials from
// `coel-bambu-setup`, i.e. the keyring). The printer is only reachable over
// Tailscale, so "unreachable" is routine: an idle printer just disappears, a print
// that was running stays on the island greyed out with when it was last seen,
// until it would have finished anyway.
//
//   printing          ambient: progress ring + %                (card on hover)
//   paused            ambient: pause glyph + %, orange
//   paused + fault    interrupt "Print failed" (resume / cancel / dismiss)
//   failed            interrupt (dismiss)
//   finished          glance 4 s with the camera frame
//
// `island demo print|pause|fault|fail|done` switches to mock data; `island demo live`
// goes back to the printer.
Scope {
  id: src
  property var engine

  // ---- data (filled by the daemon, or by demo()) ----
  property bool configured: false
  property bool reachable: false
  property real lastSeen: 0
  property string name: "Bambu P1S"
  // idle | printing | paused | failed | finished
  property string status: "idle"
  // A pause or stop the printer did by itself (spaghetti detection, runout, ...).
  property bool fault: false
  property string errorCode: ""
  property string mockError: ""
  property string file: ""
  property int pct: 0
  property int layer: 0
  property int totalLayers: 0
  property int remainingMin: 0
  property real nozzle: 0
  property real nozzleTarget: 0
  property real bed: 0
  property real bedTarget: 0
  property string speed: "standard"
  property int fan: 0
  property string snapshot: ""
  property real snapshotAt: 0
  property real startedAt: 0

  // ---- derived ----
  property real now: Date.now()
  Timer {
    interval: 30000
    repeat: true
    running: src.status === "printing" || src.status === "paused"
    onTriggered: src.now = Date.now()
  }
  // Last-known print while the printer is out of reach.
  readonly property bool stale: !mock && !reachable && lastSeen > 0
  // ...given up on once it would have finished (plus slack) without us hearing.
  readonly property bool staleExpired: stale && now - lastSeen > (remainingMin + 30) * 60000
  readonly property bool active: (status === "printing" || status === "paused") && !staleExpired
  readonly property bool alarming: status === "failed" || (status === "paused" && fault)

  function hhmm(ms) { return Qt.formatDateTime(new Date(ms), "hh:mm"); }
  function fmtDur(min) {
    const h = Math.floor(min / 60), m = min % 60;
    return h > 0 ? h + "h " + m + "m" : m + "m";
  }
  readonly property string shortFile: file.replace(/\.(gcode\.)?3mf$|\.gcode$/, "")
  readonly property string statusText: stale ? "unreachable · seen " + hhmm(lastSeen)
    : (fault && status === "paused") ? "paused by the printer" : status
  readonly property string remainingText: fmtDur(remainingMin) + " left"
  readonly property string nozzleText: Math.round(nozzle) + " / " + Math.round(nozzleTarget) + "°"
  readonly property string bedText: Math.round(bed) + " / " + Math.round(bedTarget) + "°"
  readonly property string snapshotLabel: snapshotAt ? "CAM · " + hhmm(snapshotAt) : "CAM"
  readonly property string errorText: mock ? mockError
    : (status === "failed" ? "The printer stopped the print" : "The printer paused the print by itself")
      + (errorCode ? " (error " + errorCode + ")" : "") + ". Check the camera before resuming."

  readonly property var chips: {
    if (!active) return [];
    const base = { id: "printer", source: src, prio: 50, card: cardComp, label: shortFile };
    if (stale)
      return [Object.assign(base, { parts: [[P.ring(pct, P.C.mu), P.text(pct + "%", P.C.mu, 12),
        P.icon("wifi-slash", P.C.mu, 11)]], value: "offline · seen " + hhmm(lastSeen), valueColor: P.C.mu })];
    if (status === "printing")
      return [Object.assign(base, { parts: [[P.ring(pct, P.C.cy), P.text(pct + "%", P.C.fg, 12)]],
        value: pct + "% · " + fmtDur(remainingMin), valueColor: P.C.cy })];
    const c = fault ? P.C.err : P.C.or;
    return [Object.assign(base, { parts: [[P.icon("pause", c, 11, true), P.text(pct + "%", c, 12)]],
      value: "paused · " + pct + "%", valueColor: c })];
  }

  Component { id: cardComp; PrinterCard {} }
  Component { id: failDrop; PrinterFailedDrop {} }

  // ---- transitions ----
  function raiseAlarm() {
    engine.interrupt({
      id: "print-failed", source: src, accent: P.C.err, drop: failDrop,
      parts: [P.icon("warning-octagon", P.C.err, 14, true), P.text("Print failed", P.C.err),
              P.muted("· layer " + layer + "/" + totalLayers)]
    });
  }
  // The finished glance waits briefly for the camera frame the daemon grabs right after.
  property bool doneGlancePending: false
  function showDone() {
    doneGlancePending = false;
    doneWait.stop();
    engine.glance({
      id: "print-done", source: src, ms: 4000,
      parts: [P.thumb(26, 18, snapshot), P.text("Print finished"),
              P.muted("· " + shortFile + (startedAt ? " · " + fmtDur(Math.round((Date.now() - startedAt) / 60000)) : "")),
              P.icon("check", P.C.gr, 13)]
    });
  }
  Timer { id: doneWait; interval: 3000; onTriggered: if (src.doneGlancePending) src.showDone() }
  onSnapshotChanged: if (doneGlancePending) showDone()

  function after(prev, prevAlarm) {
    if (alarming && !prevAlarm) raiseAlarm();
    else if (!alarming && prevAlarm) engine.withdraw("print-failed");
    if (status === "finished" && (prev === "printing" || prev === "paused")) {
      if (mock) showDone();
      else { doneGlancePending = true; doneWait.restart(); }
    }
    if (status === "idle") startedAt = 0;
    else if (status === "printing" && !startedAt) startedAt = Date.now();
  }

  // ---- daemon ----
  // Its first report after (re)starting only syncs state: no glance, no alarm,
  // or every Quickshell reload would announce the last print again.
  property bool primed: false
  function ingest(line) {
    let m;
    try { m = JSON.parse(line); } catch (e) { return; }
    if (m.type === "config") { configured = m.ok; if (!m.ok) console.log("printer:", m.error); }
    else if (m.type === "reach") { reachable = m.ok; if (m.last_seen) lastSeen = m.last_seen; now = Date.now(); }
    else if (m.type === "snapshot") { if (!mock) { snapshotAt = m.at; snapshot = "file://" + m.path; } }
    else if (m.type === "ack") {
      if (!m.ok) engine.glance({ id: "printer-cmd", source: src, ms: 4000,
        parts: [P.icon("printer", P.C.mu, 14), P.text("Couldn't " + m.cmd), P.muted("· " + m.error)] });
    }
    else if (m.type === "state" && !mock) {
      const prev = status, prevAlarm = alarming;
      reachable = true;
      lastSeen = m.seen;
      name = m.name; fault = m.fault; errorCode = m.error_code; file = m.file;
      pct = m.pct; layer = m.layer; totalLayers = m.total_layers; remainingMin = m.remaining_min;
      nozzle = m.nozzle; nozzleTarget = m.nozzle_target; bed = m.bed; bedTarget = m.bed_target;
      speed = m.speed; fan = m.fan;
      if (m.start_time > 0) startedAt = m.start_time * 1000;
      status = m.status;
      if (primed) after(prev, prevAlarm);
      primed = true;
    }
  }

  Process {
    id: daemon
    command: ["python3", Qt.resolvedUrl("../../scripts/coel-bambu.py").toString().replace("file://", "")]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: data => src.ingest(data) }
    stderr: SplitParser { onRead: data => console.log(data) }
    onExited: (code) => { src.primed = false; src.reachable = false; restart.start(); }
  }
  // Crashed or killed: come back, but never in a tight loop.
  Timer { id: restart; interval: 10000; onTriggered: daemon.running = true }

  function send(cmd) {
    if (mock) return mockCommand(cmd);
    if (daemon.running) daemon.write(JSON.stringify({ cmd: cmd }) + "\n");
  }

  // ---- actions ----
  function pause() { send("pause"); }
  function resume() { send("resume"); }
  function stop() { send("stop"); }
  function openStudio() { Quickshell.execDetached(["gtk-launch", "com.bambulab.BambuStudio"]); }

  // ---- mock (UI testing) ----
  property bool mock: false
  function mockCommand(cmd) {
    const prev = status, prevAlarm = alarming;
    if (cmd === "pause") status = "paused";
    else if (cmd === "resume") { fault = false; status = "printing"; }
    else if (cmd === "stop") { fault = false; status = "idle"; }
    after(prev, prevAlarm);
  }
  function demo(what) {
    if (what === "live") { mock = false; status = "idle"; primed = false; send("refresh"); return; }
    mock = true;
    const prevAlarm = alarming;
    let prev = status;
    const start = () => {
      prev = "printing";
      file = "arm-bracket_v3.gcode.3mf"; totalLayers = 480; snapshot = ""; snapshotAt = 0;
      nozzle = 220; nozzleTarget = 220; bed = 60; bedTarget = 60; fan = 80; speed = "standard";
      fault = false; pct = 38; startedAt = Date.now() - 64 * 60000; status = "printing";
    };
    if (what === "print") start();
    else if (what === "pause") { if (!active) start(); fault = false; status = "paused"; }
    else if (what === "fault") {
      if (!active) start();
      mockError = "Spaghetti detection paused the print at " + pct + " %. Nozzle held at 220°.";
      fault = true; status = "paused";
    }
    else if (what === "fail") {
      if (!active) start();
      mockError = "The printer stopped the print: heatbed temperature malfunction.";
      fault = true; status = "failed";
    }
    else if (what === "done") { if (!active) start(); pct = 100; layer = totalLayers; remainingMin = 0; status = "finished"; }
    else { fault = false; status = "idle"; }
    after(what === "print" ? "idle" : prev, prevAlarm);
  }
  onPctChanged: if (mock) { layer = Math.round(totalLayers * pct / 100); remainingMin = Math.round((100 - pct) * 2.3); }
  Timer {
    interval: 1500
    repeat: true
    running: src.mock && src.status === "printing"
    onTriggered: src.pct >= 99 ? src.demo("done") : src.pct += 1
  }
}

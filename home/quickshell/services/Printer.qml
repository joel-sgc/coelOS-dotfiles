pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../modes"

// Bambu P1S, shared by the pill (island/sources/PrinterSource.qml) and the
// desktop's printer card. Talks to ../scripts/coel-bambu.py (LAN MQTT + camera;
// credentials from `coel-bambu-setup`, i.e. the keyring).
//
// The printer is only reachable over Tailscale, so "unreachable" is routine: an
// idle printer just goes quiet; a print that was running stays (stale, greyed)
// with when it was last seen, until it would have finished anyway.
//
// Signals for the pill: alarmChanged(on) (failed, or paused by the printer),
// finished() (once the end-of-print camera frame is in, or after 3 s),
// commandFailed(cmd, error). The first report after the daemon (re)starts only
// syncs: reloads must not replay "finished" / "failed".
//
// `quickshell ipc ... call island demo print|pause|fault|fail|done|heat|live`
// drives it with mock data for UI testing.
Singleton {
  id: pr

  // ---- data (filled by the daemon, or by demo()) ----
  property bool configured: false
  property bool reachable: false
  property real lastSeen: 0
  property string name: "Bambu P1S"
  // idle | heating | printing | paused | failed | finished
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
  property int amsLoaded: 0
  property int amsTotal: 0
  property string snapshot: ""
  property real snapshotAt: 0
  property real startedAt: 0
  // When a print we were watching ended (0: it ended before we were looking).
  property real endedAt: 0

  signal alarmChanged(bool on)
  signal finished()
  signal commandFailed(string cmd, string error)

  // ---- derived ----
  property real now: Date.now()
  Timer { interval: 30000; repeat: true; running: pr.status !== "idle"; onTriggered: pr.now = Date.now() }
  // Last-known print while the printer is out of reach...
  readonly property bool stale: !mock && !reachable && lastSeen > 0
  // ...given up on once it would have finished (plus slack) without us hearing.
  readonly property bool staleExpired: stale && now - lastSeen > (remainingMin + 30) * 60000
  readonly property bool active: (status === "printing" || status === "paused" || status === "heating") && !staleExpired
  readonly property bool alarming: status === "failed" || (status === "paused" && fault)
  // What cards show: a finished/failed print we never watched end (the P1S keeps
  // reporting it until the next print) is just "idle", with the outcome as a note.
  readonly property bool oldEnd: (status === "finished" || status === "failed") && endedAt === 0 && !mock
  readonly property string shown: stale ? "offline" : oldEnd ? "idle" : status

  function hhmm(ms) { return Qt.formatDateTime(new Date(ms), "hh:mm"); }
  function fmtDur(min) {
    const h = Math.floor(min / 60), m = min % 60;
    return h > 0 ? h + "h " + m + "m" : m + "m";
  }
  readonly property string shortFile: file.replace(/\.(gcode\.)?3mf$|\.gcode$/, "")
  readonly property string statusText: stale ? "unreachable · seen " + hhmm(lastSeen)
    : (fault && status === "paused") ? "paused by the printer" : status
  readonly property string remainingText: fmtDur(remainingMin) + " left"
  readonly property string etaText: remainingMin > 0 ? "ETA " + hhmm(now + remainingMin * 60000) : ""
  readonly property string nozzleText: Math.round(nozzle) + " / " + Math.round(nozzleTarget) + "°"
  readonly property string bedText: Math.round(bed) + " / " + Math.round(bedTarget) + "°"
  readonly property string snapshotLabel: snapshotAt ? "CAM · " + hhmm(snapshotAt) : "CAM"
  readonly property string elapsedText: startedAt ? fmtDur(Math.round(((endedAt || now) - startedAt) / 60000)) : ""
  readonly property string errorText: mock ? mockError
    : (status === "failed" ? "The printer stopped the print" : "The printer paused the print by itself")
      + (errorCode ? " (error " + errorCode + ")" : "") + ". Check the camera before resuming."
  // "yesterday" / "today 14:02" / "Nov 24", for the idle card's last print.
  readonly property string lastWhen: {
    if (!startedAt) return "";
    const d = new Date(startedAt), n = new Date(now);
    const days = Math.round((new Date(n.getFullYear(), n.getMonth(), n.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 864e5);
    return days === 0 ? "today " + hhmm(startedAt) : days === 1 ? "yesterday" : Qt.formatDate(d, "MMM d").toLowerCase();
  }

  // ---- printing mode (modes/Modes.qml) follows the printer ----
  Binding { target: Modes; property: "printerStatus"; value: pr.staleExpired ? "idle" : pr.status }
  Binding {
    target: Modes; property: "printerWhy"
    value: pr.shortFile + (pr.status === "printing" ? " · " + pr.pct + "%" : pr.status !== "idle" ? " · " + pr.status : "")
  }
  Binding { target: Modes; property: "printerEndedAt"; value: pr.endedAt }

  // ---- transitions ----
  property bool donePending: false
  Timer { id: doneWait; interval: 3000; onTriggered: if (pr.donePending) { pr.donePending = false; pr.finished(); } }
  onSnapshotChanged: if (donePending) { donePending = false; doneWait.stop(); finished(); }

  function after(prev, prevAlarm) {
    if ((status === "finished" || status === "failed") && prev !== status) endedAt = Date.now();
    if (status === "printing" || status === "heating") endedAt = 0;
    if (alarming !== prevAlarm) alarmChanged(alarming);
    if (status === "finished" && (prev === "printing" || prev === "paused")) {
      if (mock) finished();
      else { donePending = true; doneWait.restart(); }
    }
    if (status === "idle" && mock) startedAt = 0;
    else if ((status === "printing" || status === "heating") && !startedAt) startedAt = Date.now();
  }

  // ---- daemon ----
  property bool primed: false
  function ingest(line) {
    let m;
    try { m = JSON.parse(line); } catch (e) { return; }
    if (m.type === "config") { configured = m.ok; if (!m.ok) console.log("printer:", m.error); }
    else if (m.type === "reach") { reachable = m.ok; if (m.last_seen) lastSeen = m.last_seen; now = Date.now(); }
    else if (m.type === "snapshot") { if (!mock) { snapshotAt = m.at; snapshot = "file://" + m.path; } }
    else if (m.type === "ack") { if (!m.ok) commandFailed(m.cmd, m.error); }
    else if (m.type === "state" && !mock) {
      const prev = status, prevAlarm = alarming;
      reachable = true;
      lastSeen = m.seen;
      name = m.name; fault = m.fault; errorCode = m.error_code; file = m.file;
      pct = m.pct; layer = m.layer; totalLayers = m.total_layers; remainingMin = m.remaining_min;
      nozzle = m.nozzle; nozzleTarget = m.nozzle_target; bed = m.bed; bedTarget = m.bed_target;
      speed = m.speed; fan = m.fan;
      amsLoaded = m.ams_loaded || 0; amsTotal = m.ams_total || 0;
      if (m.start_time > 0) startedAt = m.start_time * 1000;
      status = m.status;
      if (primed) after(prev, prevAlarm);
      primed = true;
    }
  }
  Process {
    id: daemon
    command: ["python3", Qt.resolvedUrl("../scripts/coel-bambu.py").toString().replace("file://", "")]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: data => pr.ingest(data) }
    stderr: SplitParser { onRead: data => console.log(data) }
    onExited: (code) => { pr.primed = false; pr.reachable = false; restart.start(); }
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
  function refresh() { send("refresh"); }
  function openStudio() { Quickshell.execDetached(["gtk-launch", "com.bambulab.BambuStudio"]); }
  // "cleared the plate": ends printing mode for a finished/failed print.
  function clearPlate() { Modes.clearPlate(); }

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
      amsLoaded = 3; amsTotal = 4;
      fault = false; pct = 38; startedAt = Date.now() - 64 * 60000; status = "printing";
    };
    if (what === "print") start();
    else if (what === "heat") {
      file = "arm-bracket_v3.gcode.3mf"; pct = 0; nozzle = 168; nozzleTarget = 220; bed = 52; bedTarget = 60;
      startedAt = Date.now(); status = "heating"; prev = "idle";
    }
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
    running: pr.mock && pr.status === "printing"
    onTriggered: pr.pct >= 99 ? pr.demo("done") : pr.pct += 1
  }
}

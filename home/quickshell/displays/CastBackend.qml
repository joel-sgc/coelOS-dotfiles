import Quickshell
import Quickshell.Io
import QtQuick
import "../widgets"

// ===== CAST BACKEND =====
// State + logic for the "cast" tab of the displays modal. Drives the real
// casting stack:
//   miracast  coel-miracast scan / json / cast <addr> --source portal / stop
//   gcast     coel-gcast scan --json / cast <addr:port> --source portal / stop
//   airplay   listed via coel-cast-scan, always unsupported (no sender on linux)
// Both engines run as transient *user units*, so a cast keeps going when this
// modal closes; on open the engines' status files are probed to re-attach.
// COEL_CAST_DUMMY=1 swaps in the timer-driven fake devices used to try the UI.
Item {
  id: cast
  visible: false

  signal closeRequested()
  signal toast(string kind, string title, string sub)

  readonly property bool dummy: Quickshell.env("COEL_CAST_DUMMY") === "1"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property var palette: [Pal.blue, Pal.green, Pal.yellow, Pal.purple, Pal.cyan, Pal.orange]

  // ----- devices: real scan results (or the dummy catalogue) -----
  property var devices: []
  readonly property var found: devices.map(d => d.id)
  property string errorText: ""
  property string scanNote: ""
  readonly property var catalog: [
    { id: "lr", name: "Living room TV", model: "LG C2 · webOS", proto: "miracast", icon: "television-simple", color: Pal.blue, signal: 4, max: 2160, pin: false, unsupported: false },
    { id: "bd", name: "Bedroom", model: "Chromecast with Google TV", proto: "google cast", icon: "screencast", color: Pal.green, signal: 3, max: 2160, pin: false, unsupported: false },
    { id: "mr", name: "Meeting room", model: "Microsoft Wireless Display", proto: "miracast", icon: "projector-screen", color: Pal.yellow, signal: 2, max: 1080, pin: true, unsupported: false },
    { id: "ft", name: "Office Fire TV", model: "Fire TV Stick 4K", proto: "miracast", icon: "television", color: Pal.purple, signal: 3, max: 2160, pin: false, unsupported: false },
    { id: "ap", name: "Apple TV", model: "tvOS", proto: "airplay", icon: "apple-logo", color: Pal.dim, signal: 2, max: 2160, pin: false, unsupported: true }
  ]
  function dev(id) { return devices.find(d => d.id === id) || null; }

  // ----- state -----
  property string phase: "list"          // list | pin | connecting | live
  property bool scanning: false
  property int sel: 0
  property string source: "mirror"       // mirror | extend
  property int res: 1080
  property int fps: 30
  property bool audio: true
  property string pin: ""
  property string pinErr: ""
  property int step: 0
  property var steps: []
  property string target: ""
  property var live: null                // { id, start, source, res, fps, audio }
  property real now: Date.now()
  property int spin: 0

  readonly property string spinner: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[spin % 10]
  readonly property var selDev: dev(found[sel])
  readonly property var liveDev: live ? dev(live.id) : null
  readonly property int shownRes: selDev ? Math.min(res, selDev.max) : res

  function resLabel(r) { return r === 2160 ? "4k" : r + "p"; }
  function fmtTime(ms) {
    const t = Math.floor(ms / 1000);
    return String(Math.floor(t / 60)).padStart(2, "0") + ":" + String(t % 60).padStart(2, "0");
  }

  // ----- timers -----
  Timer {
    interval: 80; repeat: true
    running: cast.scanning || cast.phase === "connecting"
    onTriggered: cast.spin++
  }
  Timer {
    interval: 1000; repeat: true; running: cast.live !== null
    onTriggered: cast.now = Date.now()
  }
  property var scanTimers: []
  property var connTimers: []
  Component { id: timerComp; Timer { property var fn; onTriggered: { fn(); destroy(); } } }
  function later(list, ms, fn) {
    const t = timerComp.createObject(cast, { interval: ms, fn: fn });
    t.start();
    list.push(t);
  }
  function clearTimers(list) { for (const t of list) { if (t) t.destroy(); } list.length = 0; }

  // ----- discovery -----
  property var mDevs: []
  property var gDevs: []
  property var aDevs: []
  property int scanPending: 0
  property int mTicks: 0
  function assemble() {
    devices = mDevs.concat(gDevs, aDevs);
    if (sel >= devices.length) sel = Math.max(0, devices.length - 1);
  }
  function rssiBars(r) { return r === null || r === undefined ? 3 : r > -50 ? 4 : r > -60 ? 3 : r > -70 ? 2 : 1; }

  function scan() {
    if (dummy) return dummyScan();
    if (scanning) return;
    scanning = true; mDevs = []; gDevs = []; aDevs = []; devices = []; sel = 0; scanNote = ""; errorText = "";
    scanPending = 2; mTicks = 0;
    mScanProc.running = true;
    mPoll.restart();
    gScanProc.running = true;
    aScanProc.running = true;
  }
  function scanPartDone() {
    scanPending = Math.max(0, scanPending - 1);
    if (scanPending === 0 && !mPoll.running) scanning = false;
  }
  Process {
    id: mScanProc
    command: ["coel-miracast", "scan", "15"]
    stderr: SplitParser { onRead: line => { if (line.trim()) cast.scanNote = "miracast: " + line.trim(); } }
  }
  Process {
    id: mStateProc
    command: ["coel-miracast", "json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const st = JSON.parse(text);
          cast.mDevs = (st.peers || []).filter(p => p.is_sink).map((p, i) => ({
            id: "m:" + p.address, name: p.name || p.address, model: "Miracast sink", proto: "miracast",
            icon: "television", color: cast.palette[i % cast.palette.length], signal: cast.rssiBars(p.rssi),
            max: 1080, pin: false, unsupported: false, busy: !!(p.wfd && p.wfd.session_available === false),
            addr: p.address, port: 0 }));
          cast.assemble();
        } catch (e) {}
      }
    }
  }
  // Polls the daemon's peer list while its scan runs (~12s).
  Timer {
    id: mPoll
    interval: 1000; repeat: true
    onTriggered: {
      mStateProc.running = true;
      if (++cast.mTicks >= 12) { mPoll.stop(); if (cast.scanPending === 0) cast.scanning = false; }
    }
  }
  Process {
    id: gScanProc
    command: ["coel-gcast", "scan", "4", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          cast.gDevs = JSON.parse(text).map((d, i) => ({
            id: "g:" + d.address + ":" + d.port, name: d.name, model: d.model || "Cast device", proto: "google cast",
            icon: /tv/i.test(d.model || "") ? "television-simple" : "screencast",
            color: cast.palette[(i + 1) % cast.palette.length], signal: 3, max: 1080, pin: false, unsupported: false,
            busy: false, addr: d.address, port: d.port }));
          cast.assemble();
        } catch (e) { if (!cast.scanNote) cast.scanNote = "google cast scan failed"; }
        cast.scanPartDone();
      }
    }
  }
  Process {
    id: aScanProc
    command: ["coel-cast-scan"]
    stdout: StdioCollector {
      onStreamFinished: {
        const out = [], seen = {};
        for (const line of text.split("\n")) {
          const m = line.match(/^_airplay\._tcp\s\s(.*)\s\s(\S+)$/);
          if (!m || seen[m[1]]) continue;
          seen[m[1]] = true;
          out.push({ id: "a:" + m[2], name: m[1], model: "AirPlay receiver", proto: "airplay", icon: "apple-logo",
            color: Pal.dim, signal: 3, max: 2160, pin: false, unsupported: true, busy: false, addr: m[2], port: 0 });
        }
        cast.aDevs = out;
        cast.assemble();
        cast.scanPartDone();
      }
    }
  }

  // ----- connecting -----
  function connectSelected() {
    const d = selDev;
    if (!d || d.unsupported || phase !== "list") return;
    if (live && live.id === d.id) { phase = "live"; return; }
    if (d.pin) { pin = ""; pinErr = ""; phase = "pin"; return; }
    run(d, false);
  }
  function pair() {
    const digits = pin.replace(/\D/g, "");
    if (digits.length !== 8) {
      pinErr = digits.length ? (8 - digits.length) + " more digit" + (8 - digits.length === 1 ? "" : "s") : "enter the pin shown on the screen";
      return;
    }
    run(selDev, true);
  }
  property var pendingDev: null
  property bool castCancelled: false
  property string lastErr: ""
  function run(d, paired) {
    if (dummy) return dummyRun(d, paired);
    errorText = ""; lastErr = ""; castCancelled = false; gotLine = false;
    pendingDev = d; target = d.id; phase = "connecting"; step = 0;
    const rl = resLabel(Math.min(res, d.max));
    if (source === "extend") {
      steps = ["creating virtual output CAST-1 · " + rl];
      extProc.command = ["sh", "-c", "hyprctl output create headless CAST-1; hyprctl keyword monitor 'CAST-1," + (rl === "720p" ? "1280x720" : "1920x1080") + "@" + fps + ",auto,1'"];
      extProc.running = true;
    } else {
      steps = ["starting " + d.proto + " session"];
      startCast(d);
    }
  }
  Process { id: extProc; onExited: { if (cast.phase === "connecting" && !cast.castCancelled) { cast.step = 1; cast.startCast(cast.pendingDev); } } }
  function startCast(d) {
    const r = Math.min(res, d.max);
    if (d.proto === "miracast")
      castProc.command = ["coel-miracast", "cast", d.addr, "--source", "portal"].concat(audio ? [] : ["--audio-source", "silence"]);
    else
      castProc.command = ["coel-gcast", "cast", d.addr + ":" + d.port, "--source", "portal", "--resolution", r >= 1080 ? "1080p" : "720p", "--fps", String(fps)].concat(audio ? [] : ["--no-audio"]);
    castProc.running = true;
  }
  Process {
    id: castProc
    environment: ({ PYTHONUNBUFFERED: "1" })
    stdout: SplitParser {
      onRead: line => {
        const t = line.trim();
        if (!t) return;
        // The first line replaces the "starting…" placeholder (extend keeps its own step).
        const base = cast.gotLine || cast.source === "extend" ? cast.steps : [];
        cast.gotLine = true;
        cast.steps = base.concat([t]);
        cast.step = cast.steps.length - 1;
      }
    }
    stderr: SplitParser { onRead: line => { if (line.trim()) cast.lastErr = line.trim(); } }
    onExited: (code) => cast.castExited(code)
  }
  property bool gotLine: false
  function castExited(code) {
    if (castCancelled) return;
    const d = pendingDev;
    if (code === 0) {
      step = steps.length;
      const last = steps[steps.length - 1] || "";
      const m = last.match(/(\d+)x(\d+)@(\d+)/);
      live = { id: d.id, start: Date.now(), source: source, res: m ? Number(m[2]) : Math.min(res, d.max), fps: m ? Number(m[3]) : fps, audio: audio };
      now = Date.now();
      phase = "live";
      liveMisses = 0;
      toast("cast", "casting to " + d.name, (source === "extend" ? "extended display" : "mirroring laptop") + " · " + resLabel(live.res) + " @" + live.fps);
    } else {
      errorText = lastErr || ("cast failed (exit " + code + ")");
      phase = "list";
      toast("stop", "cast failed", errorText);
      stopProc.command = stopCommand(d);
      stopProc.running = true;
    }
  }
  function stopCommand(d) {
    const base = d.proto === "miracast" ? "coel-miracast stop" : "coel-gcast stop";
    return ["sh", "-c", base + (source === "extend" || (live && live.source === "extend") ? "; hyprctl output remove CAST-1" : "")];
  }

  // ----- stopping -----
  property string stopToast: ""
  function cancel() {
    if (dummy) { clearTimers(connTimers); phase = live ? "live" : "list"; return; }
    castCancelled = true;
    castProc.running = false;
    stopToast = "";
    stopProc.command = stopCommand(pendingDev || selDev);
    stopProc.running = true;
    phase = live ? "live" : "list";
  }
  function stop() {
    if (!live) return;
    const d = dev(live.id), began = live.start;
    if (dummy) { live = null; phase = "list"; toast("stop", "casting stopped", d.name + " · " + fmtTime(Date.now() - began)); return; }
    stopToast = d.name + " · " + fmtTime(Date.now() - began);
    stopProc.command = stopCommand(d);
    stopProc.running = true;
    live = null; phase = "list";
    toast("stop", "casting stopped", stopToast);
  }
  Process { id: stopProc }

  // ----- live session: watch the engine, re-attach on open -----
  property int liveMisses: 0
  function statusFile() { return runtimeDir + "/" + (liveDev && liveDev.proto === "google cast" ? "gcast-source.json" : "miracast-source.json"); }
  Process {
    id: liveProc
    command: ["cat", cast.statusFile()]
    stdout: StdioCollector {
      onStreamFinished: {
        let st = {};
        try { st = JSON.parse(text); } catch (e) {}
        if (st.state === "streaming" || st.state === "casting") { cast.liveMisses = 0; return; }
        if (++cast.liveMisses >= 2) cast.liveEnded(st);
      }
    }
  }
  Timer {
    interval: 2000; repeat: true
    running: cast.live !== null && !cast.dummy
    onTriggered: liveProc.running = true
  }
  function liveEnded(st) {
    if (!live) return;
    const d = dev(live.id);
    toast("stop", "casting ended", (d ? d.name : "device") + (st && (st.error || st.reason) ? " · " + (st.error || st.reason) : ""));
    live = null;
    if (phase === "live") phase = "list";
  }
  // On open: an engine already running means a cast is in progress.
  Process {
    id: probeProc
    command: ["sh", "-c", "cd \"$XDG_RUNTIME_DIR\" 2>/dev/null || exit 0; cat miracast-source.json 2>/dev/null; echo '@@'; cat gcast-source.json 2>/dev/null; echo '@@'; coel-miracast json 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("@@");
        const j = i => { try { return JSON.parse(parts[i]); } catch (e) { return null; } };
        const m = j(0), g = j(1), link = j(2);
        let d = null, mode = null;
        if (m && m.state === "streaming") {
          const name = link && link.link && link.link.name ? link.link.name : "Miracast display";
          d = { id: "m:active", name: name, model: "Miracast sink", proto: "miracast", icon: "television", color: Pal.blue,
                signal: 3, max: 1080, pin: false, unsupported: false, busy: false, addr: link && link.link ? (link.link.peer || "") : "", port: 0 };
          mode = m.mode || {};
        } else if (g && g.state === "casting") {
          d = { id: "g:active", name: g.device || "Cast device", model: "Cast device", proto: "google cast", icon: "screencast", color: Pal.green,
                signal: 3, max: 1080, pin: false, unsupported: false, busy: false, addr: "", port: 8009 };
          mode = {};
        }
        if (!d || cast.live) return;
        cast.devices = [d].concat(cast.devices.filter(x => x.id !== d.id));
        cast.live = { id: d.id, start: Date.now(), source: "mirror", res: mode.height || 1080, fps: mode.fps || 30, audio: true };
        cast.phase = "live";
      }
    }
  }
  Component.onCompleted: { if (!dummy) probeProc.running = true; }

  // ----- dummy mode (COEL_CAST_DUMMY=1) -----
  function dummyScan() {
    clearTimers(scanTimers);
    scanning = true; devices = []; sel = 0;
    catalog.forEach((d, i) => later(scanTimers, 450 + i * 380, () => { devices = devices.concat([d]); }));
    later(scanTimers, 450 + catalog.length * 380 + 500, () => { scanning = false; });
  }
  function dummyRun(d, paired) {
    const rl = resLabel(Math.min(res, d.max)), s = [];
    if (live) s.push("stopped cast to " + dev(live.id).name);
    if (source === "extend") s.push("created virtual output CAST-1 · " + rl);
    if (d.proto === "miracast") {
      s.push("wi-fi direct group with " + d.name);
      if (paired) s.push("pin accepted");
      s.push("rtsp session · h.264 " + rl + " @" + fps);
    } else {
      s.push("connecting to " + d.name);
      s.push("launching default media receiver");
    }
    s.push("stream started");
    clearTimers(connTimers);
    steps = s; step = 0; target = d.id; phase = "connecting";
    let t = 0;
    s.forEach((_, i) => { t += 450 + Math.random() * 300; later(connTimers, t, () => { step = i + 1; }); });
    later(connTimers, t + 300, () => {
      live = { id: d.id, start: Date.now(), source: source, res: Math.min(res, d.max), fps: fps, audio: audio };
      now = Date.now();
      phase = "live";
      toast("cast", "casting to " + d.name, (source === "extend" ? "extended display" : "mirroring laptop") + " · " + rl + " @" + fps);
    });
  }
  function cycleRes() {
    const opts = [720, 1080, 1440, 2160].filter(r => !selDev || r <= selDev.max);
    const i = opts.indexOf(shownRes);
    res = opts[(i + 1) % opts.length];
  }
  function changeDevice() { phase = "list"; }

  // Returns true when the key was consumed. `Tab` is handled by the modal.
  function handleKey(k) {
    if (phase === "list") {
      if (k === "Escape") closeRequested();
      else if (k === "j" || k === "ArrowDown") sel = Math.max(0, Math.min(found.length - 1, sel + 1));
      else if (k === "k" || k === "ArrowUp") sel = Math.max(0, sel - 1);
      else if (k === "Enter") connectSelected();
      else if (k === "r") scan();
      else if (k === "s") source = source === "mirror" ? "extend" : "mirror";
      else if (k === "a") audio = !audio;
      else if (k === "f") fps = fps === 30 ? 60 : 30;
      else if (k === "q") cycleRes();
      else return false;
    } else if (phase === "pin") {
      if (k === "Enter") pair();
      else if (k === "Escape") phase = "list";
      else return false;
    } else if (phase === "connecting") {
      if (k === "Escape") cancel(); else return false;
    } else if (phase === "live") {
      if (k === "x") stop();
      else if (k === "c") changeDevice();
      else if (k === "Escape" || k === "Enter") closeRequested();
      else return false;
    } else return false;
    return true;
  }

  // ----- footer / hints (consumed by the modal) -----
  readonly property var hints: phase === "list"
    ? [["j k", "device"], ["⏎", "connect"], ["s", "mirror/extend"], ["q", "quality"], ["f", "fps"], ["a", "audio"], ["r", "rescan"], ["tab", "displays"]]
    : phase === "pin" ? [["⏎", "pair"], ["esc", "back"]]
    : phase === "connecting" ? [["esc", "cancel"]]
    : [["x", "stop"], ["c", "change device"], ["esc", "close"]]

  readonly property bool pinFull: pin.replace(/\D/g, "").length === 8
  readonly property bool canConnect: !!selDev && !selDev.unsupported
  readonly property bool sameAsLive: canConnect && live !== null && live.id === selDev.id
  readonly property string secondaryLabel: phase === "live" ? "close" : phase === "pin" ? "back" : "cancel"
  readonly property string primaryLabel: phase === "pin" ? "pair"
    : phase === "connecting" ? "connecting " + spinner
    : phase === "live" ? "stop casting"
    : !canConnect ? "connect" : sameAsLive ? "casting ›" : live ? "switch to " + selDev.name.toLowerCase() : "connect"
  readonly property color primaryBg: phase === "pin" ? (pinFull ? Pal.blue : Pal.muted)
    : phase === "connecting" ? Pal.yellow
    : phase === "live" ? Pal.red
    : canConnect ? Pal.blue : Pal.muted
  readonly property bool primaryDisabled: phase === "connecting" || (phase === "list" && !canConnect)
  readonly property real primaryOpacity: (phase === "list" && !canConnect) || (phase === "pin" && !pinFull) ? 0.55 : 1
  function primary() {
    if (phase === "list") connectSelected();
    else if (phase === "pin") pair();
    else if (phase === "live") stop();
  }
  function secondary() {
    if (phase === "live") closeRequested();
    else if (phase === "pin") phase = "list";
    else if (phase === "connecting") cancel();
    else closeRequested();
  }
}

import QtQuick
import "../.."
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../Phosphor.js" as Phosphor
import "../components"

// ===== SYSTEM DROPDOWN =====
// Phase 6a: layout matching the design mock, state fully hardcoded.
// Real /proc, /sys, and process-table wiring comes in phase 6b, once
// this is approved.
//
// By far the widest/tallest dropdown so far (the mock itself caps it at
// min(900px, 100vw-24px) rather than a fixed width like every other
// dropdown) -- cpu/memory/disks/network summary panels plus a full
// sortable/filterable/killable process table.
//
// History graphs (cpu total, network down/up) reuse Sparkline.qml, the
// same bottom-aligned RowLayout+Layout.alignment shape
// PowerDropdown.qml's wattage history already proved out -- a plain Row
// can't do per-bar variable-height bottom alignment (it fights the
// delegate's own sizing for control of y), RowLayout with
// Layout.alignment can.
//
// Process rows use manual x/anchors positioning (ProcessRow.qml) for the
// same reason as every other multi-column row in this codebase.
Item {
  id: dropdownRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  property bool popupOpen: false

  signal closeRequested()

  // ----- header -----
  property string uptime: "—"
  property string loadAvg: "—"
  readonly property string hostUser: Quickshell.env("USER") || "user"
  property string hostName: "coelos"

  Component.onCompleted: {
    hostnameProc.running = true;
    cpuModelProc.running = true;
    cpuTempPathProc.running = true;
  }
  Process {
    id: hostnameProc
    command: ["hostname"]
    stdout: StdioCollector { onStreamFinished: dropdownRoot.hostName = text.trim() }
  }
  Process {
    id: sysInfoProc
    command: ["sh", "-c", "cat /proc/uptime /proc/loadavg"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");
        if (lines.length < 2) return;
        const upSec = parseFloat(lines[0].split(" ")[0]);
        const h = Math.floor(upSec / 3600), m = Math.floor((upSec % 3600) / 60);
        dropdownRoot.uptime = h > 0 ? (h + "h " + m + "m") : (m + "m");
        dropdownRoot.loadAvg = lines[1].trim().split(" ").slice(0, 3).join(", ");
      }
    }
  }
  Timer {
    interval: 3000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: sysInfoProc.running = true
  }

  // ----- cpu -----
  property string cpuModel: "—"
  property real cpuTemp: 0
  property real cpuFreq: 0
  property int cpuTotal: 0
  property var cpuHistory: Array.from({ length: 60 }, () => 0)
  property var cores: []
  Process {
    id: cpuModelProc
    command: ["sh", "-c", "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2"]
    stdout: StdioCollector { onStreamFinished: dropdownRoot.cpuModel = text.trim() }
  }

  // k10temp's hwmon index isn't stable across reboots/kernel updates, so
  // it's discovered once by sensor name rather than a hardcoded
  // /sys/class/hwmon/hwmonN path -- same "never hardcode a path that can
  // move" principle as the battery-device and GP route-fix discovery
  // elsewhere in this repo. Falls back to acpitz (present on most x86
  // boards regardless of CPU vendor) if k10temp (AMD-specific) isn't
  // there.
  property string cpuTempPath: ""
  Process {
    id: cpuTempPathProc
    // Two separate passes, not one loop checking both names -- hwmon*
    // glob order is lexicographic, not numeric (hwmon4 sorts before
    // hwmon5), so a single "k10temp or acpitz, whichever comes first"
    // loop can pick the generic acpitz zone sensor over the real k10temp
    // CPU die sensor purely because of directory ordering, even when
    // k10temp genuinely exists (confirmed live: happened on this exact
    // machine). k10temp is only skipped if a full pass finds no match.
    command: ["sh", "-c", "p=''; for d in /sys/class/hwmon/hwmon*; do n=$(cat \"$d/name\" 2>/dev/null); if [ \"$n\" = k10temp ]; then p=\"$d/temp1_input\"; break; fi; done; if [ -z \"$p\" ]; then for d in /sys/class/hwmon/hwmon*; do n=$(cat \"$d/name\" 2>/dev/null); if [ \"$n\" = acpitz ]; then p=\"$d/temp1_input\"; break; fi; done; fi; echo \"$p\""]
    stdout: StdioCollector {
      onStreamFinished: {
        dropdownRoot.cpuTempPath = text.trim();
        if (dropdownRoot.cpuTempPath.length > 0) cpuTempProc.running = true;
      }
    }
  }
  Process {
    id: cpuTempProc
    command: ["cat", dropdownRoot.cpuTempPath]
    stdout: StdioCollector {
      onStreamFinished: {
        const milli = parseInt(text.trim());
        if (!isNaN(milli)) dropdownRoot.cpuTemp = milli / 1000;
      }
    }
  }

  // Per-core and aggregate usage from /proc/stat, diffed against the
  // previous sample (same technique Cpu.qml's bar-icon sampler already
  // uses for the aggregate figure, just kept across ticks here instead
  // of sleeping 0.3s inline, and done for every core at once).
  property var lastCpuTimes: ({})
  Process {
    id: cpuStatProc
    command: ["sh", "-c", "grep '^cpu' /proc/stat; grep 'cpu MHz' /proc/cpuinfo"]
    stdout: StdioCollector {
      onStreamFinished: {
        const times = {};
        const freqs = [];
        for (const line of text.split("\n")) {
          if (line.indexOf("cpu MHz") === 0) {
            const v = parseFloat(line.split(":")[1]);
            if (!isNaN(v)) freqs.push(v);
          } else if (line.indexOf("cpu") === 0) {
            const parts = line.trim().split(/\s+/);
            if (!/^cpu\d*$/.test(parts[0])) continue;
            const nums = parts.slice(1, 9).map(Number); // user nice system idle iowait irq softirq steal
            times[parts[0]] = { idle: nums[3] + nums[4], total: nums.reduce((a, b) => a + b, 0) };
          }
        }
        if (freqs.length > 0) dropdownRoot.cpuFreq = (freqs.reduce((a, b) => a + b, 0) / freqs.length) / 1000;

        const prev = dropdownRoot.lastCpuTimes;
        if (prev["cpu"] && times["cpu"]) {
          const dIdle = times["cpu"].idle - prev["cpu"].idle;
          const dTotal = times["cpu"].total - prev["cpu"].total;
          dropdownRoot.cpuTotal = dTotal > 0 ? Math.max(0, Math.min(100, Math.round((1 - dIdle / dTotal) * 100))) : dropdownRoot.cpuTotal;
          dropdownRoot.cpuHistory = dropdownRoot.cpuHistory.slice(1).concat([dropdownRoot.cpuTotal / 100]);

          const newCores = [];
          for (let i = 0; times["cpu" + i] && prev["cpu" + i]; i++) {
            const dI = times["cpu" + i].idle - prev["cpu" + i].idle;
            const dT = times["cpu" + i].total - prev["cpu" + i].total;
            newCores.push({ pct: dT > 0 ? Math.max(0, Math.min(100, Math.round((1 - dI / dT) * 100))) : 0 });
          }
          if (newCores.length > 0) dropdownRoot.cores = newCores;
        }
        dropdownRoot.lastCpuTimes = times;
      }
    }
  }
  Timer {
    interval: 2000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      cpuStatProc.running = true;
      if (dropdownRoot.cpuTempPath.length > 0) cpuTempProc.running = true;
    }
  }

  // ----- memory -----
  property real memUsedGb: 0
  property real memTotalGb: 1
  property real memCacheGb: 0
  property real memAvailGb: 0
  property real swapUsedGb: 0
  property real swapTotalGb: 0

  Process {
    id: memInfoProc
    command: ["sh", "-c", "grep -E '^(MemTotal|MemAvailable|Cached|Buffers|SwapTotal|SwapFree):' /proc/meminfo"]
    stdout: StdioCollector {
      onStreamFinished: {
        const kb = {};
        for (const line of text.split("\n")) {
          const m = line.match(/^(\w+):\s+(\d+)/);
          if (m) kb[m[1]] = parseInt(m[2]);
        }
        const toGb = (k) => (k || 0) / 1024 / 1024;
        dropdownRoot.memTotalGb = toGb(kb.MemTotal) || 1;
        dropdownRoot.memAvailGb = toGb(kb.MemAvailable);
        dropdownRoot.memUsedGb = Math.max(0, dropdownRoot.memTotalGb - dropdownRoot.memAvailGb);
        dropdownRoot.memCacheGb = toGb((kb.Cached || 0) + (kb.Buffers || 0));
        dropdownRoot.swapTotalGb = toGb(kb.SwapTotal);
        dropdownRoot.swapUsedGb = Math.max(0, dropdownRoot.swapTotalGb - toGb(kb.SwapFree));
      }
    }
  }
  Timer {
    interval: 3000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: memInfoProc.running = true
  }

  // ----- disks -----
  property var disks: []
  Process {
    id: disksProc
    command: ["sh", "-c", "df -B1 --output=target,fstype,source,size,used,avail 2>/dev/null | tail -n +2"]
    stdout: StdioCollector {
      onStreamFinished: {
        // tmpfs/proc/sysfs/etc are pseudo filesystems, not real storage;
        // fuse.*/nfs/cifs are remote mounts, whose free space is some
        // other machine's disk, not this one's -- neither belongs here.
        const skipFs = ["tmpfs", "devtmpfs", "proc", "sysfs", "cgroup2", "squashfs", "overlay", "efivarfs", "devpts", "securityfs", "pstore", "debugfs", "tracefs", "configfs", "mqueue", "hugetlbfs", "bpf", "autofs", "binfmt_misc"];
        const seen = {};
        const out = [];
        for (const line of text.split("\n")) {
          const parts = line.trim().split(/\s+/);
          if (parts.length < 6) continue;
          const [target, fstype, source, size, used, avail] = parts;
          if (skipFs.includes(fstype) || fstype.startsWith("fuse.") || fstype === "nfs" || fstype === "nfs4" || fstype === "cifs") continue;
          // Btrfs subvolumes of the same volume (common on NixOS --
          // /nix, /home, /, etc. often share one underlying device) all
          // report identical size/used/avail; only the first mount of
          // a given source+fstype is kept rather than listing the same
          // real free space four times over.
          const key = source + ":" + fstype;
          if (seen[key]) continue;
          seen[key] = true;
          out.push({
            mount: target,
            device: source.replace(/^\/dev\/(mapper\/)?/, ""),
            meta: fstype,
            totalGb: parseInt(size) / (1024 * 1024 * 1024),
            usedGb: parseInt(used) / (1024 * 1024 * 1024),
            freeGb: parseInt(avail) / (1024 * 1024 * 1024),
          });
        }
        // /boot pinned to the top regardless of df's own (mount-order)
        // ordering -- a stable sort so everything else keeps whatever
        // relative order df gave it.
        out.sort((a, b) => (a.mount === "/boot" ? 0 : 1) - (b.mount === "/boot" ? 0 : 1));
        dropdownRoot.disks = out;
      }
    }
  }
  Timer {
    interval: 10000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: disksProc.running = true
  }

  // ----- network -----
  readonly property var wifiDevice: {
    for (const dev of Networking.devices.values) {
      if (dev.type === DeviceType.Wifi) return dev;
    }
    return null;
  }
  readonly property string netIface: wifiDevice ? wifiDevice.name : "—"
  property real netDownRate: 0
  property real netUpRate: 0
  property string netRxTotal: "—"
  property string netTxTotal: "—"
  property var netDownHistory: Array.from({ length: 40 }, () => 0)
  property var netUpHistory: Array.from({ length: 40 }, () => 0)
  property double lastRxBytes: -1
  property double lastTxBytes: -1
  property double lastNetSampleMs: 0
  onNetIfaceChanged: { lastRxBytes = -1; lastTxBytes = -1; lastNetSampleMs = 0; }

  function fmtBytes(b) {
    if (b >= 1e12) return (b / 1e12).toFixed(1) + " TB";
    if (b >= 1e9) return (b / 1e9).toFixed(0) + " GB";
    if (b >= 1e6) return (b / 1e6).toFixed(0) + " MB";
    return (b / 1e3).toFixed(0) + " KB";
  }
  // The net section's status line (rightContent below) is one unbounded
  // Text sized to its own content (Section.qml's rightSlot has no max
  // width -- it just grows left from the panel's right edge), so a long
  // SSID pushed the whole line past the panel's left edge instead of
  // wrapping. Truncating just the SSID keeps the actually-live numbers
  // (link rate, throughput) always fully visible, which matter more
  // moment-to-moment than seeing the whole network name.
  function elideSsid(s) {
    return s.length > 14 ? s.slice(0, 13) + "…" : s;
  }
  Process {
    id: netStatsProc
    command: ["sh", "-c", "cat '/sys/class/net/" + dropdownRoot.netIface + "/statistics/rx_bytes' '/sys/class/net/" + dropdownRoot.netIface + "/statistics/tx_bytes' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");
        if (lines.length < 2) return;
        const rx = parseFloat(lines[0]), tx = parseFloat(lines[1]);
        const now = Date.now();
        if (dropdownRoot.lastNetSampleMs > 0 && rx >= dropdownRoot.lastRxBytes && tx >= dropdownRoot.lastTxBytes) {
          const dt = (now - dropdownRoot.lastNetSampleMs) / 1000;
          if (dt > 0) {
            dropdownRoot.netDownRate = (rx - dropdownRoot.lastRxBytes) / dt / 1024 / 1024;
            dropdownRoot.netUpRate = (tx - dropdownRoot.lastTxBytes) / dt / 1024 / 1024;
            dropdownRoot.netDownHistory = dropdownRoot.netDownHistory.slice(1).concat([Math.min(1, dropdownRoot.netDownRate / 20)]);
            dropdownRoot.netUpHistory = dropdownRoot.netUpHistory.slice(1).concat([Math.min(1, dropdownRoot.netUpRate / 4)]);
          }
        }
        dropdownRoot.lastRxBytes = rx;
        dropdownRoot.lastTxBytes = tx;
        dropdownRoot.lastNetSampleMs = now;
        dropdownRoot.netRxTotal = dropdownRoot.fmtBytes(rx);
        dropdownRoot.netTxTotal = dropdownRoot.fmtBytes(tx);
      }
    }
  }
  Timer {
    interval: 2000
    running: dropdownRoot.popupOpen && dropdownRoot.netIface !== "—"
    repeat: true
    triggeredOnStart: true
    onTriggered: netStatsProc.running = true
  }

  property string netSsid: ""
  property string netLinkRate: ""
  Process {
    id: netSsidProc
    command: ["sh", "-c", "nmcli -t -f active,ssid,rate dev wifi 2>/dev/null | grep '^yes'"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.trim().split(":");
        dropdownRoot.netSsid = parts.length >= 2 ? parts[1] : "";
        dropdownRoot.netLinkRate = parts.length >= 3 ? parts[2] : "";
      }
    }
  }
  Timer {
    interval: 8000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: netSsidProc.running = true
  }

  // ----- processes -----
  // comm/user are assumed space-free (true by convention for both --
  // POSIX usernames and typical binary names), so the regex splits pid/
  // comm/user/nlwp/rss/pcpu as plain whitespace-separated tokens and
  // lets the final group (the actual command line) absorb everything
  // remaining, spaces included.
  property var processes: []
  Process {
    id: processesProc
    command: ["sh", "-c", "ps -eo pid,comm:32,user,nlwp,rss,pcpu,args --no-headers --sort=-pcpu"]
    stdout: StdioCollector {
      onStreamFinished: {
        // ps/nmcli/df/etc are this dropdown's own polling commands
        // (processesProc itself included) -- excluded, not just noisy.
        // A freshly-spawned, very-short-lived process's %CPU (ps's own
        // "cpu time used / process age" ratio) can come out wildly
        // inflated -- 200%+, confirmed live -- purely from timing
        // resolution on a process that's only existed for a few
        // milliseconds, not from it actually using that much CPU. That
        // artifact is specific to sampling processes THIS young, which
        // in practice mostly means this dropdown's own helpers.
        const selfSpawned = new Set(["ps", "nmcli", "df", "cat", "grep", "cut", "sh", "hostname"]);
        const out = [];
        for (const line of text.split("\n")) {
          const m = line.match(/^\s*(\d+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s+([\d.]+)\s*(.*)$/);
          if (!m) continue;
          const rssKb = parseInt(m[5]);
          if (rssKb <= 0) continue; // kernel threads etc. -- no real memory footprint, not user-relevant
          const name = m[2];
          if (selfSpawned.has(name)) continue;
          out.push({
            pid: parseInt(m[1]), name, user: m[3],
            // ps's own pcpu is percent of ONE core (so a single-threaded
            // process pegging a core reads 100% regardless of core
            // count, and a multi-threaded one can read 300%+) -- dividing
            // by the actual core count here matches the "total" figure
            // at the top of the panel, which is already normalized
            // across all cores from /proc/stat. dropdownRoot.cores.length
            // over a literal nproc since it's the same live core count
            // the per-core cpu grid above already uses.
            thr: parseInt(m[4]), memMb: rssKb / 1024,
            cpu: parseFloat(m[6]) / Math.max(1, dropdownRoot.cores.length),
            cmd: m[7].length > 0 ? m[7] : name,
          });
        }
        // Reassigning `processes` (a plain JS array) hands the ListView a
        // brand-new model every 2.5s tick, which resets its contentY to 0
        // -- there's no diffing against the old array to know it's "the
        // same list, mostly." Note which process was at the top before
        // the reassignment, and scroll straight back to that same pid
        // (wherever it lands after re-sorting) on the next event-loop
        // turn, once the view has relaid out against the new model, so a
        // routine refresh doesn't yank whoever's scrolled down back to
        // the top.
        const topPid = dropdownRoot.topVisibleProcess ? dropdownRoot.topVisibleProcess.pid : -1;
        dropdownRoot.processes = out;
        Qt.callLater(() => dropdownRoot.restoreScrollToPid(topPid));
      }
    }
  }
  Timer {
    interval: 2500
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: processesProc.running = true
  }

  property string sortKey: "cpu" // "cpu" | "mem" | "name" | "pid"
  property bool sortDesc: true
  property string query: ""
  property int selPid: -1
  property var pendingKill: null // { pid, name, user }

  function fmtMem(mb) {
    if (mb >= 1024) return (mb / 1024).toFixed(1) + "G";
    return mb.toFixed(0) + "M";
  }
  function cycleSort() {
    const order = ["cpu", "mem", "name", "pid"];
    sortKey = order[(order.indexOf(sortKey) + 1) % order.length];
  }
  // Clicking a column header: same column again flips direction (the
  // usual table-header convention), a different column switches to it
  // and defaults back to descending.
  function setSort(key) {
    if (sortKey === key) sortDesc = !sortDesc;
    else { sortKey = key; sortDesc = true; }
  }

  readonly property var filteredProcesses: {
    const q = query.trim().toLowerCase();
    let list = processes;
    if (q.length > 0) {
      list = list.filter(p =>
        p.name.toLowerCase().includes(q) ||
        p.cmd.toLowerCase().includes(q) ||
        p.user.toLowerCase().includes(q) ||
        String(p.pid).includes(q)
      );
    }
    const sorted = list.slice().sort((a, b) => {
      let cmp;
      if (sortKey === "cpu") cmp = a.cpu - b.cpu;
      else if (sortKey === "mem") cmp = a.memMb - b.memMb;
      else if (sortKey === "pid") cmp = a.pid - b.pid;
      else cmp = a.name.localeCompare(b.name);
      return sortDesc ? -cmp : cmp;
    });
    return sorted.map(p => ({
      pid: p.pid, name: p.name, user: p.user, thr: p.thr,
      mem: fmtMem(p.memMb), cpu: p.cpu, isSel: p.pid === selPid,
    }));
  }
  readonly property var selectedProcess: processes.find(p => p.pid === selPid) || null

  // Which row is currently scrolled to the top of the list, worked out
  // from contentY alone rather than tracked separately -- every row is
  // the same height (ProcessRow.qml's fixed 20) plus the ListView's own
  // 1px spacing between them, so one full "pitch" per row divides evenly
  // into the scroll offset. Drives real by-pid scroll restoration below
  // (see processesProc.onStreamFinished).
  readonly property int procRowPitch: 21 // ProcessRow.qml height (20) + ListView spacing (1)
  // Flat +10px nudge before dividing -- confirmed by eye against the
  // debug readout that without it, a contentY sitting just a few
  // pixels into a row could still floor down to the row above. A fixed
  // pixel bias (not a per-row one) fixes it because the ambiguity is a
  // constant few pixels regardless of which row it happens on.
  readonly property int topVisibleIndex: filteredProcesses.length > 0
    ? Math.max(0, Math.min(filteredProcesses.length - 1, Math.floor((procList.contentY + 10) / procRowPitch)))
    : -1
  readonly property var topVisibleProcess: topVisibleIndex >= 0 ? filteredProcesses[topVisibleIndex] : null

  // Re-locates whatever process was at the top of the list by pid (its
  // sorted position may have moved, or it may be gone entirely) and
  // scrolls straight there -- unlike a raw contentY snapshot/restore,
  // this survives the list actually reordering between refreshes, not
  // just growing/shrinking.
  function restoreScrollToPid(pid) {
    if (pid < 0) return;
    const idx = filteredProcesses.findIndex(p => p.pid === pid);
    if (idx < 0) return;
    procList.positionViewAtIndex(idx, ListView.Beginning);
  }

  onFilteredProcessesChanged: {
    if (selPid >= 0 && !filteredProcesses.some(p => p.pid === selPid)) {
      selPid = filteredProcesses.length > 0 ? filteredProcesses[0].pid : -1;
    }
  }

  function moveSel(delta) {
    const list = filteredProcesses;
    if (list.length === 0) { selPid = -1; return; }
    const i = Math.max(0, list.findIndex(p => p.pid === selPid));
    const next = Math.max(0, Math.min(list.length - 1, i + delta));
    selPid = list[next].pid;
  }
  function askKill() {
    if (!selectedProcess) return;
    pendingKill = { pid: selectedProcess.pid, name: selectedProcess.name, user: selectedProcess.user };
  }
  // sig is "TERM" or "KILL" -- the two confirmation buttons/keys used to
  // both call one confirmKill() with no way to tell which was meant,
  // which didn't matter while this just deleted the row cosmetically,
  // but does now that a real signal goes out. No optimistic row removal
  // either -- the next processesProc tick reflects what actually
  // happened (e.g. a root-owned process this user can't signal stays
  // put, same as plain `kill` on the command line would).
  Process { id: killProc; onExited: processesProc.running = true }
  function confirmKill(sig) {
    if (!pendingKill) return;
    killProc.command = ["kill", "-" + sig, String(pendingKill.pid)];
    killProc.running = true;
    pendingKill = null;
  }
  function cancelKill() { pendingKill = null; }

  focus: true
  Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Escape) {
      // Search box swallows every other key while it has focus (typing
      // "j" types the letter, doesn't move the selection -- same as
      // every other text field in this codebase), which is correct, but
      // it means there was no way back to keybind-navigation mode
      // short of clicking. First Escape just gives focus back to the
      // dropdown; only a second Escape (now that the search box isn't
      // focused) actually closes the popup.
      if (searchInput.activeFocus) { dropdownRoot.forceActiveFocus(); event.accepted = true; return; }
      if (pendingKill) { cancelKill(); event.accepted = true; return; }
      closeRequested();
      event.accepted = true;
      return;
    }
    if (pendingKill) {
      if (event.key === Qt.Key_Y) { confirmKill("TERM"); event.accepted = true; }
      else if (event.key === Qt.Key_K && (event.modifiers & Qt.ShiftModifier)) { confirmKill("KILL"); event.accepted = true; }
      else if (event.key === Qt.Key_N) { cancelKill(); event.accepted = true; }
      else event.accepted = true;
      return;
    }
    event.accepted = true;
    switch (event.key) {
      case Qt.Key_J:
      case Qt.Key_Down:
        moveSel(1);
        break;
      case Qt.Key_K:
      case Qt.Key_Up:
        moveSel(-1);
        break;
      case Qt.Key_S:
        if (event.modifiers & Qt.ShiftModifier) sortDesc = !sortDesc;
        else cycleSort();
        break;
      case Qt.Key_Slash:
        searchInput.forceActiveFocus();
        break;
      case Qt.Key_X:
      case Qt.Key_Return:
      case Qt.Key_Enter:
        askKill();
        break;
      default:
        event.accepted = false;
    }
  }

  implicitWidth: 788
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: 0

    // ----- header -----
    RowLayout {
      width: parent.width
      height: 28
      RowLayout {
        spacing: 8
        Text { text: "system"; color: dropdownRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
        Text { text: "─ " + dropdownRoot.hostUser + "@" + dropdownRoot.hostName + " ─"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        Text { text: "up " + dropdownRoot.uptime; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
      }
      Item { Layout.fillWidth: true }
      Text { text: "load"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
      Text { text: dropdownRoot.loadAvg; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
      Text {
        text: "[×]"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.closeRequested() }
      }
    }

    Item { width: 1; height: 8 }

    // ----- cpu -----
    Section {
      width: parent.width
      label: "cpu ─ " + dropdownRoot.cpuModel
      labelColor: dropdownRoot.colors[3]
      paddingTop: 14
      paddingBottom: 10
      paddingSide: 12
      spacing: 0

      rightContent: Text {
        text: dropdownRoot.cpuTemp.toFixed(0) + "°C · " + dropdownRoot.cpuFreq.toFixed(1) + " GHz"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 12
      }

      // Manual x/anchors positioning throughout -- a RowLayout nested
      // inside a RowLayout (sparkline column + 2-column core grid, each
      // core row itself another RowLayout) hit the exact same
      // constraint-solver failure this codebase already root-caused
      // once before (PowerDropdown's profile rows): children reported
      // plausible individual bindings but the solver still handed out
      // wrong/collapsed widths in practice. Proven fix is the same one
      // used there and in every multi-column row since (DeviceRow,
      // ProcessRow): drop the nested Layouts, position explicitly.
      Item {
        width: parent.width
        height: 84

        Item {
          id: sparklineArea
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: coresBlock.left
          anchors.rightMargin: 16

          Sparkline {
            anchors.fill: parent
            anchors.bottomMargin: 1
            values: dropdownRoot.cpuHistory
            barColor: dropdownRoot.colors[3]
          }
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: dropdownRoot.hoverColor }
          Text {
            anchors.top: parent.top
            rightPadding: 6
            text: "total "
            color: dropdownRoot.fgColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
            Text { anchors.left: parent.right; text: dropdownRoot.cpuTotal + "%"; color: dropdownRoot.colors[3]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
            Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
          }
          Text {
            anchors.top: parent.top
            anchors.right: parent.right
            leftPadding: 6
            text: "60s"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 11
            Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
          }
        }

        Item {
          id: coresBlock
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          // 3 columns x 4 rows for 12 cores now, was 2x4 for 8 -- same
          // 4-row height budget (matches the sparkline's fixed 84px this
          // block shares via anchors.top/bottom), just one more column.
          width: 380

          Column {
            id: coreCol1
            x: 0
            width: 118
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
              model: dropdownRoot.cores.slice(0, 4)
              delegate: CoreRow { width: parent.width; core: modelData; coreIndex: index; fgColor: dropdownRoot.fgColor; mutedColor: dropdownRoot.mutedColor; hoverColor: dropdownRoot.hoverColor; colors: dropdownRoot.colors }
            }
          }
          Column {
            id: coreCol2
            x: 131
            width: 118
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
              model: dropdownRoot.cores.slice(4, 8)
              delegate: CoreRow { width: parent.width; core: modelData; coreIndex: index + 4; fgColor: dropdownRoot.fgColor; mutedColor: dropdownRoot.mutedColor; hoverColor: dropdownRoot.hoverColor; colors: dropdownRoot.colors }
            }
          }
          Column {
            id: coreCol3
            x: 262
            width: 118
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
              model: dropdownRoot.cores.slice(8, 12)
              delegate: CoreRow { width: parent.width; core: modelData; coreIndex: index + 8; fgColor: dropdownRoot.fgColor; mutedColor: dropdownRoot.mutedColor; hoverColor: dropdownRoot.hoverColor; colors: dropdownRoot.colors }
            }
          }
        }
      }
    }

    Item { width: 1; height: 16 }

    // ----- lower grid: (memory/disks/net) | processes -----
    // A plain Item with both columns positioned via anchors, not a
    // RowLayout -- the outer RowLayout here was the exact same failure
    // mode already found and fixed in the cpu section above: a
    // Layout.preferredWidth(300) + Layout.fillWidth pair that looked
    // correct declaratively but rendered with the first column eating
    // essentially the whole row and the second (processes) column never
    // showing at all.
    Item {
      id: lowerGrid
      width: parent.width
      height: Math.max(leftCol.implicitHeight, processesBox.height)

      ColumnLayout {
        id: leftCol
        anchors.left: parent.left
        anchors.top: parent.top
        width: 300
        spacing: 16

        Section {
          Layout.fillWidth: true
          label: "memory"
          labelColor: dropdownRoot.colors[0]
          paddingTop: 14
          paddingBottom: 10
          paddingSide: 12
          spacing: 4

          rightContent: Text {
            text: dropdownRoot.memUsedGb.toFixed(1) + "/" + dropdownRoot.memTotalGb.toFixed(1) + " GB"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }

          Item {
            width: parent.width
            height: 8
            Rectangle { anchors.fill: parent; radius: Globals.eyeCandyOff ? 0 : 1; color: "#353b45" }
            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * (dropdownRoot.memUsedGb / dropdownRoot.memTotalGb)
              radius: Globals.eyeCandyOff ? 0 : 1
              color: dropdownRoot.colors[0]
            }
            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: parent.width * (dropdownRoot.memUsedGb / dropdownRoot.memTotalGb)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * (dropdownRoot.memCacheGb / dropdownRoot.memTotalGb)
              radius: Globals.eyeCandyOff ? 0 : 1
              color: "#2bbac5"
              opacity: 0.55
            }
          }
          Item { width: 1; height: 4 }
          Repeater {
            // swap row only appears when swap actually exists -- this
            // machine has none configured at all (SwapTotal: 0 in
            // /proc/meminfo), and a usedGb/totalGb divide against a
            // real zero total would be NaN, not just an empty bar.
            model: {
              const rows = [
                { k: "used", pct: Math.round(dropdownRoot.memUsedGb / dropdownRoot.memTotalGb * 100), v: dropdownRoot.memUsedGb.toFixed(1) + "G", color: dropdownRoot.colors[0] },
                { k: "cached", pct: Math.round(dropdownRoot.memCacheGb / dropdownRoot.memTotalGb * 100), v: dropdownRoot.memCacheGb.toFixed(1) + "G", color: "#2bbac5" },
                { k: "avail", pct: Math.round(dropdownRoot.memAvailGb / dropdownRoot.memTotalGb * 100), v: dropdownRoot.memAvailGb.toFixed(1) + "G", color: dropdownRoot.colors[3] },
              ];
              if (dropdownRoot.swapTotalGb > 0) {
                rows.push({ k: "swap", pct: Math.round(dropdownRoot.swapUsedGb / dropdownRoot.swapTotalGb * 100), v: (dropdownRoot.swapUsedGb * 1000).toFixed(0) + "M/" + dropdownRoot.swapTotalGb.toFixed(1) + "G", color: dropdownRoot.colors[4] });
              }
              return rows;
            }
            delegate: RowLayout {
              required property var modelData
              width: parent.width
              spacing: 14
              Text { Layout.preferredWidth: 48; text: modelData.k; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
              Text {
                Layout.fillWidth: true
                readonly property int filled: Math.round(modelData.pct / 5)
                text: "█".repeat(filled)
                color: modelData.color
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                Text { text: "░".repeat(20 - parent.filled); color: dropdownRoot.hoverColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
              }
              Text { Layout.preferredWidth: 68; horizontalAlignment: Text.AlignRight; text: modelData.v; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            }
          }
        }

        Section {
          Layout.fillWidth: true
          label: "disks"
          labelColor: dropdownRoot.colors[2]
          paddingTop: 14
          paddingBottom: 8
          paddingSide: 12
          spacing: 6

          rightContent: Text {
            text: dropdownRoot.disks.reduce((sum, d) => sum + d.freeGb, 0).toFixed(1) + "G free total"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }

          Repeater {
            model: dropdownRoot.disks
            delegate: DiskRow {
              required property var modelData
              width: parent.width
              disk: modelData
              fgColor: dropdownRoot.fgColor
              mutedColor: dropdownRoot.mutedColor
              hoverColor: dropdownRoot.hoverColor
              colors: dropdownRoot.colors
            }
          }
        }

        Section {
          Layout.fillWidth: true
          label: "net ─ " + dropdownRoot.netIface
          labelColor: "#2bbac5"
          paddingTop: 14
          paddingBottom: 8
          paddingSide: 12
          spacing: 2

          rightContent: Text {
            text: (dropdownRoot.netSsid.length > 0 ? dropdownRoot.elideSsid(dropdownRoot.netSsid) + " · " + dropdownRoot.netLinkRate + " · " : "")
              + dropdownRoot.netDownRate.toFixed(1) + "↓ " + dropdownRoot.netUpRate.toFixed(1) + "↑ MB/s"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }

          RowLayout {
            width: parent.width
            Text { text: "↓"; color: "#2bbac5"; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            Text { text: dropdownRoot.netDownRate.toFixed(1) + " MB/s"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            Item { Layout.fillWidth: true }
            Text { text: "rx " + dropdownRoot.netRxTotal; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
          }
          Item {
            width: parent.width
            height: 26
            Sparkline { anchors.fill: parent; values: dropdownRoot.netDownHistory; barColor: "#2bbac5"; minOpacity: 0.35; maxOpacity: 1 }
          }
          RowLayout {
            width: parent.width
            Text { text: "↑"; color: dropdownRoot.colors[4]; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            Text { text: dropdownRoot.netUpRate.toFixed(1) + " MB/s"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            Item { Layout.fillWidth: true }
            Text { text: "tx " + dropdownRoot.netTxTotal; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
          }
          Item {
            width: parent.width
            height: 26
            Sparkline { anchors.fill: parent; values: dropdownRoot.netUpHistory; barColor: dropdownRoot.colors[4]; minOpacity: 0.35; maxOpacity: 1 }
          }
        }
      }

      // ----- processes -----
      Rectangle {
        id: processesBox
        anchors.left: leftCol.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.top: parent.top
        height: procCol.implicitHeight + 20
        radius: Globals.eyeCandyOff ? 0 : 2
        color: "transparent"
        border.width: 1
        border.color: "#4b5263"

        Text {
          x: 8
          y: -9
          leftPadding: 6
          rightPadding: 6
          text: "processes (" + dropdownRoot.filteredProcesses.length + ")"
          color: dropdownRoot.colors[0]
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: 8
          y: -9
          leftPadding: 6
          rightPadding: 6
          text: "[s] sort: " + dropdownRoot.sortKey + (dropdownRoot.sortDesc ? " ▼" : " ▲") + "  [S] flip"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
          MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: (mouse) => { if (mouse.modifiers & Qt.ShiftModifier) dropdownRoot.sortDesc = !dropdownRoot.sortDesc; else dropdownRoot.cycleSort(); } }
        }

        Column {
          id: procCol
          x: 8
          y: 14
          width: parent.width - 16
          spacing: 6

          RowLayout {
            id: searchRow
            width: parent.width
            spacing: 8
            Text { text: "/"; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: 20
              color: searchInput.activeFocus ? "#2c313c" : "#1e2127"
              Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: searchInput.activeFocus ? dropdownRoot.colors[2] : dropdownRoot.hoverColor }
              TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                text: dropdownRoot.query
                color: dropdownRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
                selectByMouse: true
                onTextEdited: dropdownRoot.query = text
              }
              Text {
                visible: dropdownRoot.query.length === 0 && !searchInput.activeFocus
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "filter by name, command, user or pid"
                color: dropdownRoot.mutedColor
                font.family: "JetBrains Mono"
                font.italic: true
                font.pixelSize: 12
              }
            }
            Rectangle {
              visible: dropdownRoot.query.length > 0
              implicitWidth: clearLabel.implicitWidth + 10
              implicitHeight: 18
              radius: Globals.eyeCandyOff ? 0 : 2
              color: clearMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text { id: clearLabel; anchors.centerIn: parent; text: "[clear]"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
              MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.query = "" }
            }
          }

          Item {
            id: headerRow
            width: parent.width
            height: 16
            Text { x: 22; text: "pid" + (dropdownRoot.sortKey === "pid" ? (dropdownRoot.sortDesc ? " ▼" : " ▲") : ""); anchors.verticalCenter: parent.verticalCenter; color: dropdownRoot.sortKey === "pid" ? dropdownRoot.fgColor : dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12
              MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.setSort("pid") }
            }
            Text { x: 76; text: "name" + (dropdownRoot.sortKey === "name" ? (dropdownRoot.sortDesc ? " ▼" : " ▲") : ""); anchors.verticalCenter: parent.verticalCenter; color: dropdownRoot.sortKey === "name" ? dropdownRoot.fgColor : dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12
              MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.setSort("name") }
            }
            Text { anchors.right: parent.right; anchors.rightMargin: 8; text: "cpu" + (dropdownRoot.sortKey === "cpu" ? (dropdownRoot.sortDesc ? " ▼" : " ▲") : ""); anchors.verticalCenter: parent.verticalCenter; color: dropdownRoot.sortKey === "cpu" ? dropdownRoot.fgColor : dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12
              MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.setSort("cpu") }
            }
            Text { anchors.right: parent.right; anchors.rightMargin: 58; text: "mem" + (dropdownRoot.sortKey === "mem" ? (dropdownRoot.sortDesc ? " ▼" : " ▲") : ""); anchors.verticalCenter: parent.verticalCenter; color: dropdownRoot.sortKey === "mem" ? dropdownRoot.fgColor : dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12
              MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.setSort("mem") }
            }
          }

          ListView {
            id: procList
            // Stretches to make the whole processes box match the left
            // column's height (memory/disks/net stacked), rather than
            // staying a fixed 280px regardless of how much taller that
            // column is -- everything else in procCol (search row,
            // column headers, the optional selected-process footer) is
            // fixed-size, so whatever's left over goes to the list.
            // Never shrinks below 280 either, so a short left column
            // doesn't cramp it.
            width: parent.width
            height: Math.max(280, leftCol.implicitHeight - searchRow.height - headerRow.height
              - (footerRow.visible ? footerRow.height + procCol.spacing : 0)
              - procCol.spacing * 2 - 20)
            clip: true
            spacing: 1
            model: dropdownRoot.filteredProcesses
            delegate: ProcessRow {
              width: ListView.view.width
              row: modelData
              fgColor: dropdownRoot.fgColor
              mutedColor: dropdownRoot.mutedColor
              accentColor: dropdownRoot.colors[0]
              onSelect: dropdownRoot.selPid = modelData.pid
              onKill: { dropdownRoot.selPid = modelData.pid; dropdownRoot.askKill(); }
            }
          }
          Text {
            visible: dropdownRoot.filteredProcesses.length === 0
            text: "no processes match “" + dropdownRoot.query + "”"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }

          RowLayout {
            id: footerRow
            visible: dropdownRoot.selectedProcess !== null
            width: parent.width
            spacing: 10
            Text {
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: dropdownRoot.selectedProcess ? (dropdownRoot.selectedProcess.name + " · running · " + dropdownRoot.selectedProcess.cmd) : ""
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 12
            }
            Rectangle {
              implicitWidth: killLabel.implicitWidth + 12
              implicitHeight: 18
              radius: Globals.eyeCandyOff ? 0 : 2
              color: killMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text { id: killLabel; anchors.centerIn: parent; text: "[x] kill"; color: dropdownRoot.colors[1]; font.family: "JetBrains Mono"; font.pixelSize: 12 }
              MouseArea { id: killMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.askKill() }
            }
          }
        }
      }
    }

    Item { width: 1; height: 12 }

    // ----- hints -----
    Flow {
      width: parent.width
      spacing: 14
      readonly property var hints: [
        { k: "j/k", l: "move" }, { k: "s", l: "sort" }, { k: "S", l: "asc/desc" }, { k: "/", l: "filter" }, { k: "x", l: "kill" }, { k: "esc", l: "close" },
      ]
      Repeater {
        model: parent.hints
        RowLayout {
          required property var modelData
          spacing: 4
          Text { text: modelData.k; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          Text { text: modelData.l; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        }
      }
    }
  }

  // ----- kill confirmation modal -----
  Rectangle {
    visible: dropdownRoot.pendingKill !== null
    anchors.fill: parent
    radius: Globals.eyeCandyOff ? 0 : 12
    color: "#1e2127"
    opacity: 0.82

    MouseArea { anchors.fill: parent }
  }
  Rectangle {
    visible: dropdownRoot.pendingKill !== null
    anchors.centerIn: parent
    width: Math.min(380, parent.width - 32)
    implicitHeight: killModalCol.implicitHeight + 28
    radius: Globals.eyeCandyOff ? 0 : 2
    color: "#282c34"
    border.width: 1
    border.color: dropdownRoot.colors[1]

    Text {
      x: 8
      y: -9
      leftPadding: 6
      rightPadding: 6
      text: "⚠ end process"
      color: dropdownRoot.colors[1]
      font.family: "JetBrains Mono"
      font.pixelSize: 13
      Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
    }

    Column {
      id: killModalCol
      x: 16
      y: 16
      width: parent.width - 32
      spacing: 8

      RowLayout {
        width: parent.width
        spacing: 8
        Text { text: dropdownRoot.pendingKill ? dropdownRoot.pendingKill.name : ""; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
        Text { text: dropdownRoot.pendingKill ? ("pid " + dropdownRoot.pendingKill.pid + " · " + dropdownRoot.pendingKill.user) : ""; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "This will send a termination signal to the process. Unsaved work in it may be lost."
        color: dropdownRoot.fgColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }
      Row {
        spacing: 8
        Rectangle {
          implicitWidth: termLabel.implicitWidth + 16
          implicitHeight: 22
          radius: Globals.eyeCandyOff ? 0 : 2
          color: dropdownRoot.colors[2]
          Text { id: termLabel; anchors.centerIn: parent; text: "< y SIGTERM >"; color: "#282c34"; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.confirmKill("TERM") }
        }
        Rectangle {
          implicitWidth: killLabel2.implicitWidth + 16
          implicitHeight: 22
          radius: Globals.eyeCandyOff ? 0 : 2
          color: dropdownRoot.colors[1]
          Text { id: killLabel2; anchors.centerIn: parent; text: "< K SIGKILL >"; color: "#282c34"; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.confirmKill("KILL") }
        }
        Rectangle {
          implicitWidth: cancelLabel2.implicitWidth + 16
          implicitHeight: 22
          radius: Globals.eyeCandyOff ? 0 : 2
          color: cancelMouse2.containsMouse ? dropdownRoot.hoverColor : "transparent"
          Text { id: cancelLabel2; anchors.centerIn: parent; text: "< n cancel >"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          MouseArea { id: cancelMouse2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.cancelKill() }
        }
      }
    }
  }
}

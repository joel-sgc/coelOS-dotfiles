pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// CPU/RAM/disk of the home server (ssh host "server" in ~/.ssh/config), one ssh
// round trip per poll: /proc/stat sampled twice 0.3 s apart, meminfo, df.
Singleton {
  id: root
  property string sshHost: "server"
  property string name: "jsgc-server"
  property int refreshSeconds: 30

  property bool loaded: false
  property bool failed: false
  property bool refreshing: false
  property real updatedAt: 0
  property int cpuPct: 0
  property real memUsedKb: 0
  property real memTotalKb: 0
  property real diskUsedKb: 0
  property real diskTotalKb: 0
  property real uptimeS: 0
  property string load: ""

  function pct(used, total) { return total > 0 ? Math.round(used / total * 100) : 0; }
  readonly property int ramPct: pct(memUsedKb, memTotalKb)
  readonly property int diskPct: pct(diskUsedKb, diskTotalKb)
  readonly property bool healthy: loaded && !failed && cpuPct < 90 && ramPct < 90 && diskPct < 90
  readonly property string state: failed ? "unreachable" : !loaded ? "checking…" : healthy ? "healthy" : "busy"
  readonly property string uptimeText: {
    const d = Math.floor(uptimeS / 86400), h = Math.floor(uptimeS % 86400 / 3600);
    return d > 0 ? d + "d " + h + "h" : h + "h " + Math.floor(uptimeS % 3600 / 60) + "m";
  }

  function refresh() {
    if (refreshing) return;
    refreshing = true;
    sampler.running = true;
  }
  Process {
    id: sampler
    command: [
      "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", root.sshHost,
      "read -r _ u1 n1 s1 i1 _ < /proc/stat; sleep 0.3; read -r _ u2 n2 s2 i2 _ < /proc/stat; t1=$((u1+n1+s1+i1)); t2=$((u2+n2+s2+i2)); cpu=$(( 100 - (100 * (i2-i1)) / (t2-t1) )); mt=$(awk '/MemTotal/{print $2}' /proc/meminfo); ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo); mu=$((mt-ma)); dl=$(df -k / | tail -1); dtt=$(echo $dl | awk '{print $2}'); du=$(echo $dl | awk '{print $3}'); up=$(cut -d' ' -f1 /proc/uptime); ld=$(cut -d' ' -f1 /proc/loadavg); echo \"$cpu|$mu|$mt|$du|$dtt|$up|$ld\""
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const p = text.trim().split("|"), nums = p.slice(0, 6).map(Number);
        if (p.length === 7 && nums.every(n => !isNaN(n))) {
          root.cpuPct = nums[0]; root.memUsedKb = nums[1]; root.memTotalKb = nums[2];
          root.diskUsedKb = nums[3]; root.diskTotalKb = nums[4]; root.uptimeS = nums[5];
          root.load = p[6];
          root.failed = false;
          root.loaded = true;
        } else root.failed = true;
        root.refreshing = false;
        root.updatedAt = Date.now();
      }
    }
  }
  Component.onCompleted: refresh()
  Timer { interval: root.refreshSeconds * 1000; running: true; repeat: true; onTriggered: root.refresh() }
}

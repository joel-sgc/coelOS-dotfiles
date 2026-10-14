import QtQuick
import ".."
import Quickshell.Io
import QtQuick.Layouts

// ===== SERVER STATUS WIDGET =====
// CPU/RAM/disk usage for the local home server (ssh host "server" in
// ~/.ssh/config -- an aarch64 box, in practice a Raspberry Pi), sampled the
// same way sysPanel/buttons/Cpu.qml already samples the LOCAL machine's own
// cpu usage (reading /proc/stat's aggregate line twice 0.3s apart and
// diffing), just run remotely through one ssh call instead of locally --
// one round trip per poll gathers cpu+ram+disk together rather than three
// separate connections.
DesktopWidget {
  id: root

  property string sshHost: "server"
  property int refreshSeconds: 30
  property bool showHints: true

  property bool loaded: false
  property bool failed: false
  property bool refreshing: false
  property real updatedAt: 0
  property real nowMs: Date.now()

  property int cpuPct: 0
  property real memUsedKb: 0
  property real memTotalKb: 0
  property real diskUsedKb: 0
  property real diskTotalKb: 0

  cardWidth: 300
  anchorRight: true
  anchorBottom: true

  function gb(kb) { return (kb / 1024 / 1024).toFixed(1); }
  function pct(used, total) { return total > 0 ? Math.round(used / total * 100) : 0; }
  function barColor(p) { return p >= 90 ? Pal.red : p >= 70 ? Pal.yellow : Pal.green; }

  readonly property string updatedText: {
    if (refreshing) return "checking…";
    if (failed && !loaded) return "unreachable";
    const s = Math.floor((nowMs - updatedAt) / 1000);
    if (s < 1) return "updated just now";
    if (s < 60) return "updated " + s + "s ago";
    return "updated " + Math.floor(s / 60) + "m ago";
  }

  readonly property var rows: !loaded ? [] : [
    { icon: "cpu", label: "cpu", pctVal: cpuPct, text: cpuPct + "%" },
    { icon: "memory", label: "ram", pctVal: pct(memUsedKb, memTotalKb), text: gb(memUsedKb) + " / " + gb(memTotalKb) + " gb" },
    { icon: "hard-drives", label: "disk", pctVal: pct(diskUsedKb, diskTotalKb), text: gb(diskUsedKb) + " / " + gb(diskTotalKb) + " gb" },
  ]

  function refresh() {
    if (refreshing) return;
    refreshing = true;
    sampler.running = true;
  }

  Process {
    id: sampler
    command: [
      "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", root.sshHost,
      "read -r _ u1 n1 s1 i1 _ < /proc/stat; sleep 0.3; read -r _ u2 n2 s2 i2 _ < /proc/stat; t1=$((u1+n1+s1+i1)); t2=$((u2+n2+s2+i2)); cpu=$(( 100 - (100 * (i2-i1)) / (t2-t1) )); mt=$(awk '/MemTotal/{print $2}' /proc/meminfo); ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo); mu=$((mt-ma)); dl=$(df -k / | tail -1); dtt=$(echo $dl | awk '{print $2}'); du=$(echo $dl | awk '{print $3}'); echo \"$cpu|$mu|$mt|$du|$dtt\""
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const nums = text.trim().split("|").map(Number);
        if (nums.length === 5 && nums.every(n => !isNaN(n))) {
          root.cpuPct = nums[0];
          root.memUsedKb = nums[1];
          root.memTotalKb = nums[2];
          root.diskUsedKb = nums[3];
          root.diskTotalKb = nums[4];
          root.failed = false;
          root.loaded = true;
        } else {
          root.failed = true;
        }
        root.refreshing = false;
        root.updatedAt = Date.now();
        root.nowMs = Date.now();
      }
    }
  }

  Component.onCompleted: refresh()
  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
  // keeps the "updated Ns ago" text honest
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  onKeyPressed: (e) => {
    if (e.key === Qt.Key_R) { root.refresh(); e.accepted = true; }
  }

  // ----- header -----
  RowLayout {
    Layout.fillWidth: true
    Layout.bottomMargin: 8
    spacing: 8
    PhIcon { name: "desktop-tower"; color: root.focused ? Pal.blue : Pal.dim; font.pixelSize: 14 }
    Mono { text: "server"; font.weight: Font.Medium; color: root.focused ? Pal.blue : Pal.dim }
    Mono { Layout.fillWidth: true; text: "─ " + root.sshHost + " ─"; color: Pal.muted; elide: Text.ElideRight }
    TextButton {
      onClicked: root.refresh()
      Mono { text: "[" + (root.refreshing ? "⟳" : "r") + "]"; color: Pal.muted }
    }
  }

  Box {
    Layout.fillWidth: true
    padTop: 14; padSide: 12; padBottom: 10
    spacing: 10
    legend: "usage"
    rightLegend: root.updatedText
    rightColor: root.failed ? Pal.red : (root.refreshing ? Pal.yellow : Pal.muted)

    Repeater {
      model: root.rows
      delegate: ColumnLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 4
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          PhIcon { name: modelData.icon; color: Pal.dim; font.pixelSize: 13 }
          Mono { text: modelData.label; color: Pal.muted }
          Item { Layout.fillWidth: true }
          Mono { text: modelData.text }
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 6
          radius: Globals.eyeCandyOff ? 0 : 1
          color: Pal.track
          Rectangle {
            width: parent.width * modelData.pctVal / 100
            height: parent.height
            radius: Globals.eyeCandyOff ? 0 : 1
            color: root.barColor(modelData.pctVal)
          }
        }
      }
    }

    Mono {
      visible: !root.loaded
      Layout.fillWidth: true
      Layout.topMargin: 4
      horizontalAlignment: Text.AlignHCenter
      text: root.failed ? "can't reach " + root.sshHost : "checking…"
      color: Pal.muted
    }
  }

  Hints {
    visible: root.showHints
    Layout.fillWidth: true
    Layout.topMargin: 12
    items: [["r", "refresh"]]
  }
}

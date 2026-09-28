import QtQuick
import Quickshell.Io

// ----- "About this system" real data -----
Item {
  id: root

  property var data: ({ user: "joelsgc", host: "", kernel: "", uptime: "", wm: "Hyprland", shell: "", cpu: "", memory: "", disk: "" })

  Process {
    id: proc
    command: ["sh", "-c", "hostname; uname -r; cat /proc/uptime; grep -m1 'model name' /proc/cpuinfo; nproc; grep -E '^MemTotal:|^MemAvailable:' /proc/meminfo; df -B1 --output=used,size / | tail -1; zsh --version; hyprctl version | head -1"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n");
        const host = lines[0] || "";
        const kernel = lines[1] || "";
        const uptimeSec = parseFloat((lines[2] || "0").split(" ")[0]) || 0;
        const cpuModel = (lines[3] || "").split(":")[1];
        const cores = lines[4] || "";
        const memTotalKb = parseInt((lines[5] || "0").replace(/\D/g, "")) || 0;
        const memAvailKb = parseInt((lines[6] || "0").replace(/\D/g, "")) || 0;
        const diskParts = (lines[7] || "").trim().split(/\s+/);
        const diskUsed = parseInt(diskParts[0]) || 0, diskTotal = parseInt(diskParts[1]) || 1;
        const zshVer = (lines[8] || "").split(" ")[1] || "";
        const hyprVer = (lines[9] || "").replace(/^Hyprland\s*/, "").split(" ")[0] || "";

        const uh = Math.floor(uptimeSec / 3600), um = Math.floor((uptimeSec % 3600) / 60);
        const gb = b => (b / 1073741824).toFixed(1) + "G";

        root.data = {
          user: "joelsgc", host: host.trim(),
          kernel: kernel.trim(),
          uptime: uh + "h " + String(um).padStart(2, "0") + "m",
          wm: "Hyprland " + hyprVer,
          shell: "zsh " + zshVer,
          cpu: (cpuModel ? cpuModel.trim() : "unknown") + " (" + cores.trim() + ")",
          memory: gb((memTotalKb - memAvailKb) * 1024) + " / " + gb(memTotalKb * 1024),
          disk: gb(diskUsed) + " / " + gb(diskTotal),
        };
      }
    }
  }
  Component.onCompleted: proc.running = true
}

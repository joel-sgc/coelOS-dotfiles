pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The paired phone over KDE Connect, for the desktop's phone card: battery,
// the newest notification, ring it, send it files. Polled with
// ../scripts/phone-state.py (busctl, no Python D-Bus needed): every 30 s while
// reachable, every 2 min otherwise.
Singleton {
  id: ph

  property bool paired: false
  property bool reachable: false
  property string deviceId: ""
  property string name: "phone"
  property int battery: -1
  property bool charging: false
  // {id, app, title, text, seenAt} -- seenAt is when we first saw it.
  property var notification: null
  property real now: Date.now()

  readonly property string ago: {
    if (!notification) return "";
    const m = Math.floor((now - notification.seenAt) / 60000);
    return m < 1 ? "just now" : m < 60 ? m + "m ago" : Math.floor(m / 60) + "h ago";
  }
  // One line for a minimized card: "Nothing Phone 3 · 64% · Mira: running late"
  readonly property string summary: !paired ? "no phone paired"
    : !reachable ? name + " · not connected"
    : name + (battery >= 0 ? " · " + battery + "%" : "")
      + (notification ? " · " + (notification.title || notification.app) + ": " + notification.text : "")

  function refresh() { if (!poll.running) poll.running = true; }
  Process {
    id: poll
    command: ["python3", Qt.resolvedUrl("../scripts/phone-state.py").toString().replace("file://", "")]
    stdout: StdioCollector {
      onStreamFinished: {
        let j;
        try { j = JSON.parse(text); } catch (e) { return; }
        ph.now = Date.now();
        ph.paired = !!j.ok;
        if (!j.ok) { ph.reachable = false; return; }
        ph.deviceId = j.id;
        ph.name = j.name || "phone";
        ph.reachable = !!j.reachable;
        if (!j.reachable) return;
        ph.battery = j.battery;
        ph.charging = !!j.charging;
        const n = j.notification;
        if (!n) ph.notification = null;
        else if (!ph.notification || ph.notification.id !== n.id)
          ph.notification = Object.assign({ seenAt: Date.now() }, n);
      }
    }
  }
  Component.onCompleted: refresh()
  Timer { interval: ph.reachable ? 30000 : 120000; repeat: true; running: true; onTriggered: ph.refresh() }

  // ---- actions ----
  readonly property string devPath: "/modules/kdeconnect/devices/" + deviceId
  function ring() {
    if (!reachable) return;
    Quickshell.execDetached(["busctl", "--user", "call", "org.kde.kdeconnect", devPath + "/findmyphone",
                             "org.kde.kdeconnect.device.findmyphone", "ring"]);
  }
  // Portal file chooser (coel-pick-file), then kdeconnect-cli --share each file.
  function sendFile() {
    if (!reachable || picker.running) return;
    picker.running = true;
  }
  Process {
    id: picker
    command: ["coel-pick-file", "Send to " + ph.name]
    stdout: StdioCollector {
      onStreamFinished: {
        for (const path of text.split("\n").filter(p => p !== ""))
          Quickshell.execDetached(["kdeconnect-cli", "-d", ph.deviceId, "--share", path]);
      }
    }
  }
}

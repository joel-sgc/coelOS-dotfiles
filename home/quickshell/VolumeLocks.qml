pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQml

// Locked microphone levels: whenever anything else (a browser's auto gain, a
// call app) changes a locked source's volume, it is put back. Changing it from
// the audio popup moves the lock instead (set()). Lives here, not in the popup,
// so it applies while the popup is closed. State: ~/.local/share/coel/
// volume-locks.json, { "<node.name>": 0.35 } on Quickshell's volume scale
// (same as wpctl).
Singleton {
  id: root

  property var locks: ({})
  readonly property string dir: (Quickshell.env("COEL_DATA_DIR") || Quickshell.env("HOME") + "/.local/share/coel")

  function isLocked(name) { return locks[name] !== undefined; }
  function toggle(node) {
    if (!node || !node.audio) return;
    const next = Object.assign({}, locks);
    if (next[node.name] === undefined) next[node.name] = Math.round(node.audio.volume * 100) / 100;
    else delete next[node.name];
    save(next);
  }
  // A deliberate change to a locked source.
  function set(name, volume) {
    if (!isLocked(name)) return;
    const next = Object.assign({}, locks);
    next[name] = volume;
    save(next);
  }
  function save(next) {
    locks = next;
    file.setText(JSON.stringify(next) + "\n");
  }

  FileView {
    id: file
    path: root.dir + "/volume-locks.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try { root.locks = JSON.parse(text()); } catch (e) { console.warn("volume locks: bad state file:", e); }
    }
  }

  Instantiator {
    model: Pipewire.nodes.values.filter(n => !n.isStream && (n.type & PwNodeType.AudioSource) === PwNodeType.AudioSource)
    delegate: QtObject {
      id: watch
      required property var modelData
      readonly property var target: root.locks[modelData.name]
      readonly property bool drifted: target !== undefined && modelData.ready && modelData.audio !== null
        && Math.abs(modelData.audio.volume - target) > 0.01

      property PwObjectTracker tracker: PwObjectTracker { objects: [watch.modelData] }
      // Delayed, so a device that keeps refusing can't turn this into a busy loop.
      property Timer restore: Timer {
        interval: 200
        repeat: true
        running: watch.drifted
        onTriggered: watch.modelData.audio.volume = watch.target
      }
    }
  }
}

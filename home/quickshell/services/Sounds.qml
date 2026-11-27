pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../modes"

// UI sounds. Each sound is a WAV named after its event; a "pack" is a folder of
// them. The default pack is synthesized (sounds/synth.py ->
// assets/sounds/synth/). settings.toml [sounds]:
//
//   enabled = true
//   volume  = 0.5        0..1
//   pack    = ""         folder of WAVs with the same names; any it lacks fall
//                        back to the synthesized ones; one volume.wav may stand
//                        in for every volume-N step
//
// Silent with eye candy off, and in any mode whose [modes.<name>] has
// sounds = false (Class by default). The lock screen, a separate process,
// plays lock/unlock through `ipc call sounds play <name>` so the same rules
// apply.
Singleton {
  id: sounds

  readonly property var names: {
    const n = ["toggle-on", "toggle-off", "launcher", "lock", "unlock", "chime", "alert"];
    for (let p = 0; p <= 100; p += 5) n.push("volume-" + p);
    return n;
  }
  readonly property string synthDir: Qt.resolvedUrl("../assets/sounds/synth").toString().replace("file://", "")

  // ---- settings ----
  property var cfg: ({})
  readonly property bool enabled: cfg.enabled !== false
  readonly property real volume: typeof cfg.volume === "number" ? Math.max(0, Math.min(1, cfg.volume)) : 0.5
  readonly property string pack: typeof cfg.pack === "string"
    ? cfg.pack.replace(/^~(?=\/|$)/, Quickshell.env("HOME")) : ""
  readonly property bool active: enabled && !Globals.eyeCandyOff
    && !(Modes.config[Modes.mode] && Modes.config[Modes.mode].sounds === false)

  readonly property string settingsPath: Quickshell.env("COEL_SETTINGS") || (Quickshell.env("HOME") + "/.nixos/settings.toml")
  FileView {
    path: sounds.settingsPath
    watchChanges: true
    onFileChanged: settingsProc.running = true
    onLoaded: settingsProc.running = true
  }
  Process {
    id: settingsProc
    command: ["python3", Qt.resolvedUrl("../scripts/settings-table.py").toString().replace("file://", ""), "sounds"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { sounds.cfg = JSON.parse(text) || {}; }
        catch (e) { console.warn("sounds: bad settings JSON:", e); }
      }
    }
  }

  // ---- which file plays for each name ----
  property var packFiles: []      // file names present in `pack`
  onPackChanged: {
    packFiles = [];
    if (pack !== "") { listProc.command = ["ls", "-1", pack]; listProc.running = true; }
  }
  Process {
    id: listProc
    stdout: StdioCollector { onStreamFinished: sounds.packFiles = text.split("\n").filter(s => s.endsWith(".wav")) }
  }
  readonly property var files: {
    const out = {};
    for (const n of names) {
      let f = synthDir + "/" + n + ".wav";
      if (pack !== "") {
        if (packFiles.includes(n + ".wav")) f = pack + "/" + n + ".wav";
        else if (n.startsWith("volume-") && packFiles.includes("volume.wav")) f = pack + "/volume.wav";
      }
      out[n] = f;
    }
    return out;
  }

  // ---- playback ----
  property var bank: null
  Component.onCompleted: {
    const c = Qt.createComponent(Qt.resolvedUrl("SoundBank.qml"));
    if (c.status === Component.Ready) bank = c.createObject(sounds, { volume: sounds.volume });
    else console.warn("sounds: no QtMultimedia, playing through pw-play:", c.errorString());
  }
  onFilesChanged: if (bank) {
    const urls = {};
    for (const n in files) urls[n] = "file://" + files[n];
    bank.urls = urls;
  }
  onVolumeChanged: if (bank) bank.volume = volume
  onBankChanged: filesChanged()

  function play(name) {
    if (!active || !files[name]) return;
    if (bank && bank.play(name)) return;
    Quickshell.execDetached(["pw-play", "--volume", String(volume), files[name]]);
  }

  // Level feedback (volume, brightness): the tick for the 5% step `v` (0..1)
  // lands on, pitched by the level (the volume-N sounds).
  property real lastTick: 0
  function volumeTick(v) { levelTick(v); }
  function levelTick(v) {
    const now = Date.now();
    if (now - lastTick < 35) return;    // a drag can fire faster than that
    lastTick = now;
    play("volume-" + Math.max(0, Math.min(100, Math.floor(v * 20 + 1e-3) * 5)));
  }
  function toggle(on) { play(on ? "toggle-on" : "toggle-off"); }

  // `quickshell ipc -p ~/.nixos/home/quickshell call sounds play lock`
  IpcHandler {
    target: "sounds"
    function play(name: string): void { sounds.play(name); }
    function list(): string { return JSON.stringify(sounds.files, null, 1); }
    // Why it is (or isn't) making sound.
    function status(): string {
      return JSON.stringify({ active: sounds.active, enabled: sounds.enabled, eyeCandyOff: Globals.eyeCandyOff,
                              mode: Modes.mode, volume: sounds.volume, pack: sounds.pack || "synth",
                              player: sounds.bank ? "QtMultimedia" : "pw-play" });
    }
  }
}

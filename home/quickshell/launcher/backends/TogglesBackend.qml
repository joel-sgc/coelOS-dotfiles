import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

// ----- real toggle backends (do not disturb, keep awake, mic mute,
// monochrome, eye candy) -----
// monochromeOn is re-read from its real source after every toggle (never
// assumed) -- same "don't optimistically update, wait for the next real
// read" rule SystemDropdown.qml's kill action follows, since it's state
// something *other* than this launcher could change independently
// (Hyprland's screen_shader option). awakeOn/micMuted/eyeCandyOff don't
// need that: awake is just whether our own systemd-inhibit child process
// is alive (fully our own lifecycle), mic mute mirrors a live PwNode
// property directly (no separate read-back needed), and eye candy is a
// bundle of 4 hyprctl options with no single external source of truth to
// reconcile against -- "on"/"off" is our own defined bundle, not a fact
// some other tool could independently flip.
Item {
  id: root

  // The one process-wide NotificationsBackend instance, threaded in via
  // LauncherPanel.qml <- Launcher.qml <- shell.qml.
  property var notifications: null

  // ----- do not disturb -----
  // No subprocess, no external daemon to reconcile with -- used to shell
  // out to `makoctl mode`/`makoctl mode -t dnd`, back when mako was the
  // real notification daemon and its DND flag lived entirely outside this
  // launcher's own process. Now that Quickshell's own NotificationsBackend
  // owns notifications end to end, DND is just a plain property read
  // straight off it, same as every other real-time value this launcher
  // reads directly (micMuted, etc).
  readonly property bool dndOn: notifications ? notifications.dnd : false
  function toggleDnd() { if (notifications) notifications.toggleDnd(); }

  // ----- keep awake -----
  // Held open the whole time awakeOn is true; `running: false` sends it
  // SIGTERM, which releases the inhibitor immediately (systemd-inhibit's
  // own lock lasts exactly as long as the process holding it does).
  property bool awakeOn: false
  Process {
    id: awakeProc
    command: ["systemd-inhibit", "--what=idle:sleep", "--who=CoelOS launcher", "--why=keep awake toggled from launcher", "sleep", "infinity"]
  }
  function toggleAwake() {
    awakeOn = !awakeOn;
    awakeProc.running = awakeOn;
  }

  // ----- global microphone mute (real Pipewire, not wpctl) -----
  // Same PwNode.audio.muted API AudioDropdown.qml/Volume.qml already use --
  // a PwNode is inert (its audio.* properties never update) until it's
  // inside a PwObjectTracker, hence that below. defaultAudioSource is
  // Quickshell's own "current default mic" singleton property, so this
  // tracks whatever the real default is rather than a specific device.
  readonly property var micSource: Pipewire.defaultAudioSource
  readonly property bool micMuted: micSource && micSource.audio ? micSource.audio.muted : false
  PwObjectTracker { objects: root.micSource ? [root.micSource] : [] }
  function toggleMicMute() {
    if (micSource && micSource.audio) micSource.audio.muted = !micSource.audio.muted;
  }

  // ----- monochrome (Hyprland screen shader) -----
  // decoration:screen_shader is the real, current (Hyprland 0.55.4)
  // option name -- confirmed live via `hyprctl -j getoption`; misc:
  // screen_shader (an older/alternate name seen in some docs) doesn't
  // exist on this version.
  property bool monochromeOn: false
  readonly property string monochromeShaderPath: Qt.resolvedUrl("../../scripts/monochrome.frag").toString().replace("file://", "")
  function refreshMonochrome() { monochromeCheckProc.running = true; }
  Process {
    id: monochromeCheckProc
    command: ["hyprctl", "-j", "getoption", "decoration:screen_shader"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.monochromeOn = JSON.parse(text).str === root.monochromeShaderPath;
        } catch (e) {
          root.monochromeOn = false;
        }
      }
    }
  }
  function toggleMonochrome() {
    monochromeSetProc.command = ["hyprctl", "keyword", "decoration:screen_shader", monochromeOn ? "" : monochromeShaderPath];
    monochromeSetProc.running = true;
  }
  Process {
    id: monochromeSetProc
    onExited: root.refreshMonochrome()
  }

  // ----- eye candy (animations/blur/rounding/border gradient) -----
  // Values below are the real current config (home/hyprland.nix:
  // decoration.rounding=8, general.border_size=2, theme colors from
  // home/theme/onedark.nix -- blue/yellow/comment) and Hyprland's actual
  // shipped defaults for the two options this repo never sets at all
  // (animations/blur both ship enabled, confirmed live via
  // `hyprctl -j getoption`, not assumed).
  property bool eyeCandyOff: false
  function setEyeCandy(off) {
    eyeCandyOff = off;
    const cmds = off
      ? ["animations:enabled 0", "decoration:blur:enabled 0", "decoration:rounding 0", 'general:col.active_border "rgba(5c6370ee)"']
      : ["animations:enabled 1", "decoration:blur:enabled 1", "decoration:rounding 8", 'general:col.active_border "rgba(61afefee) rgba(e5c07bee) 45deg"'];
    eyeCandyProc.command = ["sh", "-c", cmds.map(c => "hyprctl keyword " + c).join(" && ")];
    eyeCandyProc.running = true;
  }
  function toggleEyeCandy() { setEyeCandy(!eyeCandyOff); }
  Process { id: eyeCandyProc }
}

import Quickshell
import Quickshell.Wayland
import QtQuick

import "./backends"

// ===== LOCK =====
// Owns every piece of state for the lock screen (auth/power/media state
// machine, ported from the mockup's own <script data-dc-script> Component
// class in sddm-hyprlock/Lockscreen.dc.html -- submit()/succeed()/fp()/
// power()/mk()), collapsed to one flat instance rather than the mockup's
// per-preview-variant `this.state[id]` indirection, since there's only one
// real screen to drive here.
//
// Mirrors to every connected screen (Variants over Quickshell.screens,
// same idiom as Border.qml/Launcher.qml) with state lifted up to this
// Scope rather than owned per-delegate like Launcher.qml's activeScreen
// gate -- a lock screen covers the whole desktop, not a single-screen
// modal, and the real ext-session-lock-v1 protocol requires a surface on
// every output anyway. One flat set of state, props/signals down to the
// purely presentational LockScreen.qml.
//
// `real` picks which of two coexisting surface implementations is live:
// - false (lock-shell.qml, the dev harness): a plain PanelWindow, visible
//   unconditionally, killable like any other quickshell test -- safe for
//   ongoing UI tweaks without ever touching the real session-lock protocol.
// - true (lock-real-shell.qml, wired into hypridle.nix/the $mainMod+L bind):
//   Quickshell.Wayland's actual WlSessionLock/WlSessionLockSurface, backed
//   by the real ext-session-lock-v1 protocol -- genuinely blocks input to
//   everything else until authBackend confirms a real PAM success.
// Only the mode `real` selects ever actually engages (the other's `locked`/
// `visible` binds to false), so there's no risk of the dev harness ever
// accidentally holding a real lock.
Scope {
  id: lockRoot

  property bool real: false

  // ----- colors (this project has no shared theme singleton -- see
  // shell.qml/Launcher.qml, every top-level file hardcodes the same
  // onedark-derived hex values and passes them down as props) -----
  property color bgColor: "#282c34"
  property color fgColor: "#abb2bf"
  property color brightColor: "#d7dae0"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property color inputBg: "#1e2127"
  property color rowBg: "#2f343e"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]

  AuthBackend { id: authBackend }

  // Real lock mode only ever shows/authenticates the actual current user
  // -- a lock screen can't sensibly offer to unlock as someone else, and
  // there's no real multi-user backend to back that anyway (see below).
  readonly property var realUser: ({
    name: authBackend.username || "user",
    init: (authBackend.username || "user").charAt(0).toUpperCase(),
  })

  // ----- static demo data, login-mode preview only -----
  // Login/greetd is still separate, future work (see STATUS.md) -- this
  // mode stays a fake, non-authenticating preview of that eventual screen
  // (real multi-user enumeration + real session list + real greetd IPC are
  // all still to come), gated off entirely in real mode below so a real
  // session lock never exposes a dead-end "switch user" path.
  readonly property var demoUsers: [
    { name: "coel", init: "C" },
    { name: "guest", init: "G" },
    { name: "work", init: "W" },
  ]
  readonly property var demoSessions: ["Hyprland", "Niri", "Sway", "TTY"]
  readonly property var demoTracks: [
    { title: "Midnight City", artist: "M83", dur: 243 },
    { title: "Intro", artist: "The xx", dur: 128 },
    { title: "Teardrop", artist: "Massive Attack", dur: 331 },
  ]
  readonly property var powerActions: [
    { id: "suspend", icon: "moon", label: "suspend", command: ["systemctl", "suspend"] },
    { id: "reboot", icon: "arrow-clockwise", label: "reboot", command: ["systemctl", "reboot"] },
    { id: "poweroff", icon: "power", label: "power off", command: ["systemctl", "poweroff"] },
  ]
  // Real enrollment status, not a fixed toggle -- see AuthBackend's own
  // comment: the fingerprint icon is now purely a passive "is this even
  // available" indicator, always listening in the background rather than
  // something click-triggered.
  readonly property bool fpOn: authBackend.fingerprintEnrolled
  readonly property var mountedAt: new Date()

  // ----- auth/mode state -----
  property string mode: "lock" // "lock" | "login"
  property int selectedUser: 0
  property int selectedSession: 0
  property string pw: ""
  property bool showPw: false
  // Stand-in for real CapsLock detection (still no clean QML-native way to
  // read the lock-key state itself). Toggled via F9 while the password
  // field has focus, forwarded up from AuthCard.qml.
  property bool debugCapsOn: false
  property int errCount: 0
  property string authState: "idle" // idle | checking | ok
  property var msg: null // {icon, text, color}
  property int shakeSeq: 0
  property string armedPower: ""

  function pad(n) { return String(n).padStart(2, "0"); }
  readonly property string lockedAtText: {
    const d = new Date(mountedAt.getTime() - 12 * 60000);
    return pad(d.getHours()) + ":" + pad(d.getMinutes());
  }

  readonly property var statusLine: {
    if (msg && authState !== "idle") return msg;
    if (debugCapsOn) return { icon: "arrow-fat-up", text: "caps lock is on", color: colors[2] };
    if (msg) return msg;
    return {
      icon: "",
      text: mode !== "lock" ? "choose a user and session"
        : fpOn ? "enter password or touch the sensor"
        : "enter your password",
      color: mutedColor,
    };
  }

  function freshAuth() {
    pw = "";
    showPw = false;
    errCount = 0;
    authState = "idle";
    msg = null;
  }
  function setMode(m) {
    if (m === mode) return;
    // Real mode never exposes the login-mode preview -- see the demo-data
    // comment above for why (no real backend behind it, and a real
    // session lock shouldn't dead-end into one).
    if (real && m === "login") return;
    mode = m;
    if (m === "lock") selectedUser = 0;
    freshAuth();
  }
  function pickUser(i) {
    selectedUser = i;
    freshAuth();
  }
  function sessionStep(delta) {
    selectedSession = (selectedSession + delta + demoSessions.length) % demoSessions.length;
  }
  function triggerShake() { shakeSeq++; }

  function submitPassword() {
    if (authState !== "idle") return;
    if (pw.length === 0) {
      triggerShake();
      msg = { icon: "info", text: "enter your password", color: mutedColor };
      return;
    }
    authState = "checking";
    msg = { icon: "circle-notch", text: "checking…", color: mutedColor };
    if (mode === "lock") authBackend.checkPassword(pw);
    else submitCheckTimer.restart(); // login-mode preview only, see below
  }
  // Login-mode preview only -- demo password, matches the mockup's own
  // documented "coel". Lock mode's real result comes back via
  // authBackend.passwordResult instead (Connections below).
  function onSubmitCheckFinished() {
    handlePasswordResult(pw === "coel", "");
  }
  // `error` is empty for a routine failure (AuthBackend.qml's PamContext
  // handlers only pass a non-empty PamResult/PamError diagnostic string
  // for a genuine backend problem, never for an ordinary wrong password/
  // no-match) and for the fake login-mode path above. Showing that real
  // text instead of a blanket "incorrect password" is what would have
  // told a previous real-mode test the PAM service hadn't been switched
  // in yet, rather than leaving it looking like an unwinnable "wrong
  // password" loop with no escape.
  function isBackendError(error) {
    return !!error;
  }
  function handlePasswordResult(success, error) {
    if (success) { succeedAuth(); return; }
    authState = "idle";
    triggerShake();
    if (isBackendError(error)) {
      msg = { icon: "x", text: "auth backend error: " + error, color: colors[1] };
      return;
    }
    errCount++;
    pw = "";
    msg = { icon: "x", text: "incorrect password" + (errCount > 1 ? " · " + errCount + " attempts" : ""), color: colors[1] };
  }
  function succeedAuth() {
    const isLock = mode === "lock";
    authState = "ok";
    msg = {
      icon: "check",
      text: isLock
        ? "unlocked · welcome back"
        : "starting " + demoSessions[selectedSession].toLowerCase() + " as " + demoUsers[selectedUser].name + "…",
      color: colors[3],
    };
    if (real) {
      // The real ext-session-lock-v1 surface disappears the instant this
      // fires -- no time for the "welcome back" message above to actually
      // be seen, same as swaylock/hyprlock's own behavior on success.
      // Give the unlock a moment to actually land before the process
      // exits, rather than racing it.
      //
      // Plain property assignment, not sessionLock.unlock() -- AGENTS.md's
      // own already-learned lesson (a .qmltypes Method entry isn't a
      // guarantee of real QML invokability, confirmed once already this
      // project with a different Quickshell type) applies here too, and
      // this is the one call in this whole file that must not silently
      // fail: `locked` is a real Property with a real setter, so this is
      // guaranteed to work the way a Method call isn't.
      sessionLock.locked = false;
      quitTimer.start();
      return;
    }
    successResetTimer.restart();
  }
  // Fingerprint is continuous now, not click-triggered (AuthBackend loops
  // it on its own) -- this just reacts to whatever it reports, whenever it
  // reports it, independent of whatever the password field's own authState
  // happens to be doing at that moment (typing a password and touching the
  // sensor are meant to be genuinely parallel options, same as real
  // hyprlock's own two independent backends).
  Connections {
    target: authBackend
    function onPasswordResult(success, error) {
      if (lockRoot.authState !== "checking") return;
      lockRoot.handlePasswordResult(success, error);
    }
    function onFingerprintResult(success, error) {
      if (success) { lockRoot.succeedAuth(); return; }
      // Deliberately quiet on an ordinary failed/no-match verify -- this
      // retries on its own forever in the background, so surfacing a
      // message on every routine attempt would be noisy for something the
      // user may not have even consciously triggered. Only a genuine
      // backend problem (not just "no match") is worth interrupting the
      // password field's own status line for.
      if (lockRoot.isBackendError(error)) {
        lockRoot.msg = { icon: "x", text: "fingerprint backend error: " + error, color: lockRoot.colors[1] };
      }
    }
  }

  function armOrFirePower(action) {
    if (armedPower !== action.id) {
      armedPower = action.id;
      powerArmTimer.restart();
      return;
    }
    powerArmTimer.stop();
    armedPower = "";
    msg = { icon: "circle-notch", text: "→ " + action.command.join(" "), color: mutedColor };
    // Only actually runs in real mode -- the dev harness (lock-shell.qml)
    // is for UI iteration and shouldn't be able to suspend/reboot/power
    // off the machine it's being tested on.
    if (real) Quickshell.execDetached(action.command);
  }

  // ----- fake media playback -----
  property bool playing: true
  property int trackIndex: 0
  property int posSeconds: 83
  readonly property var currentTrack: demoTracks[trackIndex]
  function mediaToggle() { playing = !playing; }
  function mediaPrev() {
    if (posSeconds > 3) posSeconds = 0;
    else {
      posSeconds = 0;
      trackIndex = (trackIndex + demoTracks.length - 1) % demoTracks.length;
    }
  }
  function mediaNext() {
    posSeconds = 0;
    trackIndex = (trackIndex + 1) % demoTracks.length;
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (!lockRoot.playing) return;
      const dur = lockRoot.currentTrack.dur;
      if (lockRoot.posSeconds + 1 >= dur) {
        lockRoot.posSeconds = 0;
        lockRoot.trackIndex = (lockRoot.trackIndex + 1) % lockRoot.demoTracks.length;
      } else {
        lockRoot.posSeconds++;
      }
    }
  }
  Timer { id: submitCheckTimer; interval: 550; onTriggered: lockRoot.onSubmitCheckFinished() }
  Timer { id: successResetTimer; interval: 1800; onTriggered: lockRoot.freshAuth() }
  Timer { id: powerArmTimer; interval: 3000; onTriggered: lockRoot.armedPower = "" }
  Timer { id: quitTimer; interval: 80; onTriggered: Qt.quit() }

  // ----- real session lock (real === true only) -----
  WlSessionLock {
    id: sessionLock
    locked: lockRoot.real

    surface: Component {
      WlSessionLockSurface {
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#2c313a" }
            GradientStop { position: 0.55; color: "#23272e" }
            GradientStop { position: 1.0; color: "#1c1f24" }
          }
        }

        LockScreenBridge {}
      }
    }
  }

  // ----- dev harness surface (real === false only) -----
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData

        visible: !lockRoot.real

        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#2c313a" }
            GradientStop { position: 0.55; color: "#23272e" }
            GradientStop { position: 1.0; color: "#1c1f24" }
          }
        }

        LockScreenBridge {}
      }
    }
  }
}

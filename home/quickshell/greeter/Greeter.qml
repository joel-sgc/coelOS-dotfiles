import Quickshell
import QtQuick

import "./backends"
import "../lock"

// ===== GREETER =====
// Login screen sharing the lock screen's own visual chrome -- reuses
// LockScreen.qml (and everything it composes: MediaWidget/NetworkBattery/
// ClockDate/AuthCard) directly from ../lock/ rather than duplicating it,
// since those components already just take plain props/emit signals and
// know nothing about which backend drives them (PamContext for the lock
// screen, GreeterBackend/Quickshell.Services.Greetd here). AuthCard's own
// mode: "lock"|"login" split and its user-switcher/session-stepper UI were
// originally built as a fake login-mode *preview* of exactly this future
// screen -- this is that preview becoming real.
//
// Unlike Lock.qml, there's no real-vs-dev-harness surface duality to
// juggle here: a greeter is just a normal fullscreen window whether it's
// being previewed in a window or actually running under greetd/cage --
// there's no analogous "real session-lock protocol" to gate behind a flag
// the way WlSessionLock needed one. GreeterBackend's own `mock` property
// (true whenever Quickshell.Services.Greetd.available is false) is what
// distinguishes real from preview here instead.
//
// Plain FloatingWindow (a real xdg-toplevel), not PanelWindow/
// WlrLayershell like Lock.qml uses -- confirmed live (real hardware, not
// just the VM) that cage/quickshell were both genuinely running, not
// crashed, but produced no visible frame at all: `cage` is a minimal
// kiosk compositor whose whole job is "fullscreen the one xdg-toplevel
// window my child app creates" and, unlike Hyprland, it doesn't implement
// wlr-layer-shell (a panel/overlay protocol a kiosk compositor has no
// reason to need) -- PanelWindow's layer-shell surface request was
// silently never satisfied. A plain window is also what the reference
// doc's own cage-targeting example used; only Lock.qml (running under the
// user's real Hyprland, which does implement layer-shell) needs the
// PanelWindow/WlrSessionLock machinery.
Scope {
  id: root

  GreeterBackend { id: backend }

  property string pw: ""
  property bool showPw: false
  readonly property string authState: backend.busy ? "checking" : "idle"
  property int shakeSeq: 0
  function triggerShake() { shakeSeq++; }

  readonly property var statusLine: backend.msg || {
    icon: "", text: "choose a user and session", color: "#5c6370",
  }

  property string armedPower: ""
  readonly property var powerActions: [
    { id: "suspend", icon: "moon", label: "suspend", command: ["systemctl", "suspend"] },
    { id: "reboot", icon: "arrow-clockwise", label: "reboot", command: ["systemctl", "reboot"] },
    { id: "poweroff", icon: "power", label: "power off", command: ["systemctl", "poweroff"] },
  ]
  Timer { id: powerArmTimer; interval: 3000; onTriggered: root.armedPower = "" }
  function armOrFirePower(action) {
    if (armedPower !== action.id) {
      armedPower = action.id;
      powerArmTimer.restart();
      return;
    }
    powerArmTimer.stop();
    armedPower = "";
    Quickshell.execDetached(action.command);
  }

  function submitPassword() {
    if (pw.length === 0) { triggerShake(); return; }
    backend.submit(pw);
  }

  Connections {
    target: backend
    function onLaunchRequested() { fadeTimer.start(); }
  }
  // A short pause before actually launching -- greetd expects the greeter
  // to exit promptly after launch, but an instant cut with zero
  // transition reads as a crash rather than a deliberate handoff. Kept
  // short per the reference doc's own warning not to delay launch().
  Timer { id: fadeTimer; interval: 150; onTriggered: backend.doLaunch() }

  // Hardcoded to the real panel's known resolution -- confirmed live
  // (real hardware log.qslog, re-checked after removing the
  // Screen.width/height binding) that cage never sends a second,
  // correct configure event after its first one: Qt logs "There are no
  // outputs - creating placeholder screen" once, then "Configure event
  // ... contains invalid width/height: 0" once, and nothing further.
  // There's no later real-size event to react to -- the window's
  // implicit size was silently falling back to Qt's tiny placeholder-
  // screen default the whole time, not to the real output size, which
  // is why AuthCard (anchored to the *right* edge of that tiny area)
  // never landed anywhere visible while ClockDate (anchored left)
  // still did. This machine has a single fixed monitor (eDP-1,
  // 2256x1504 -- confirmed in the greeter plan doc), so hardcoding
  // sidesteps the race entirely instead of trying to detect it.
  //
  // implicitWidth/Height, not width/height -- confirmed live (real
  // hardware log.qslog) that Quickshell logs "Setting `width` is
  // deprecated. Set `implicitWidth` instead." for FloatingWindow, and
  // that plain `width`/`height` genuinely did not take effect as the
  // window's real size hint: it "worked" in the windowed dev harness
  // only because Hyprland's tiling assigned the window some unrelated
  // size (1100x1436, not 2256x1504) that happened to be big enough,
  // masking the bug there. cage has no tiling WM to bail this out, so
  // the real surface stayed at Qt's tiny placeholder-screen fallback.
  FloatingWindow {
    id: win
    visible: true
    color: "transparent"
    implicitWidth: 2256
    implicitHeight: 1504

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: "#2c313a" }
        GradientStop { position: 0.55; color: "#23272e" }
        GradientStop { position: 1.0; color: "#1c1f24" }
      }
    }

    LockScreen {
      anchors.fill: parent
      mode: "login"
      users: backend.users
      selectedUser: backend.selectedUserIndex
      sessions: backend.sessions.map(s => s.name)
      selectedSession: backend.selectedSessionIndex
      pw: root.pw
      showPw: root.showPw
      authState: root.authState
      statusLine: root.statusLine
      armedPower: root.armedPower
      powerActions: root.powerActions
      shakeSeq: root.shakeSeq
      fpOn: false

      onPwEdited: (text) => root.pw = text
      onSubmitRequested: root.submitPassword()
      onToggleShowRequested: root.showPw = !root.showPw
      onPickUserRequested: (index) => backend.pickUser(index)
      onSessionStepRequested: (delta) => backend.sessionStep(delta)
      onPowerRequested: (action) => root.armOrFirePower(action)
    }
  }
}

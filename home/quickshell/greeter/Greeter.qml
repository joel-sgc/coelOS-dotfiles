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

  // Calls doLaunch() immediately, no deliberate delay -- confirmed live
  // (real hardware, auth debug log) that a 150ms Timer here (originally
  // added for a fade transition that was never actually wired to any
  // visible animation -- pure delay, zero cosmetic payoff) let the whole
  // greeter process get killed before the timer fired in 2 of 3 real
  // login attempts, meaning Greetd.launch() was never even called.
  // Collapsing the gap between "auth succeeded" and "launch requested"
  // to zero removes that window entirely.
  Connections {
    target: backend
    function onLaunchRequested() { backend.doLaunch(); }
  }

  // Sized to the FULL combined canvas, with the actual UI positioned
  // only within eDP-1's own sub-rectangle inside it -- this used to just
  // hardcode the laptop panel's own known resolution (2256x1504), because
  // cage never sends a second, correct `configure` event after its first
  // one (confirmed live: Qt logs "There are no outputs - creating
  // placeholder screen" once, then "Configure event ... contains invalid
  // width/height: 0" once, and nothing further -- the window's implicit
  // size was silently falling back to Qt's tiny placeholder-screen
  // default the whole time, which is why AuthCard, anchored to the
  // *right* edge of that tiny area, never landed anywhere visible while
  // ClockDate, anchored left, still did).
  //
  // Hardcoding one fixed size stopped being enough once a second,
  // external monitor entered the picture (confirmed live): cage's
  // multi-output mode ("extend", its only real option -- see below) spans
  // a single combined bounding box across every connected output (its
  // own upstream wiki: content that doesn't fill that whole box gets
  // positioned/clipped against it, not against any one real monitor), so
  // a fixed 2256x1504 surface was landing somewhere inside a larger
  // virtual canvas instead of filling the laptop panel -- the exact same
  // "AuthCard off-screen" symptom, new cause.
  //
  // Tried asking cage for just eDP-1 directly instead -- doesn't work.
  // `-m last` sounded like it would pick a single specific output, but
  // it actually means "whichever output connected most recently" (cage
  // -h's own wording), and on this laptop eDP-1 connects before any
  // external monitor, so "last" picked the external monitor instead,
  // putting the WHOLE greeter there rather than fixing anything. cage
  // 0.3.0 has no flag to name a specific output at all (confirmed via
  // cage -h: only extend/last exist) -- there's no way to just tell it
  // "eDP-1", so fighting cage's output selection from the launch command
  // is a dead end.
  //
  // So instead of fighting the combined bounding box, this window now
  // IS the combined bounding box, honestly: `canvasWidth`/`canvasHeight`
  // sum/max across every `Quickshell.screens` entry's own real x/y/width/
  // height (populated from `wl_output` geometry, the same mechanism
  // Border.qml/Panel.qml already rely on for real multi-monitor geometry
  // under Hyprland -- a different, more reliable data path than the
  // broken `configure`-event negotiation above), covering whatever
  // layout wlroots actually chose. The background gradient still fills
  // that whole canvas (so the external monitor just shows a plain dark
  // screen, not garbage), but the actual LockScreen UI is positioned at
  // `targetScreen`'s own x/y/width/height sub-rectangle within it --
  // `eDP-1` by name when present (this machine's real laptop panel),
  // falling back to the first screen Quickshell sees otherwise. The
  // literal 2256x1504/0,0 fallbacks only matter if `Quickshell.screens`
  // is somehow empty, which shouldn't happen in practice.
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

    readonly property var targetScreen: Quickshell.screens.find(s => s.name === "eDP-1")
      || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    readonly property real canvasWidth: Quickshell.screens.length > 0
      ? Math.max(...Quickshell.screens.map(s => s.x + s.width))
      : 2256
    readonly property real canvasHeight: Quickshell.screens.length > 0
      ? Math.max(...Quickshell.screens.map(s => s.y + s.height))
      : 1504

    implicitWidth: canvasWidth
    implicitHeight: canvasHeight

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
      x: win.targetScreen ? win.targetScreen.x : 0
      y: win.targetScreen ? win.targetScreen.y : 0
      width: win.targetScreen ? win.targetScreen.width : 2256
      height: win.targetScreen ? win.targetScreen.height : 1504
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
      fpOn: backend.fingerprintEnrolled

      onPwEdited: (text) => root.pw = text
      onSubmitRequested: root.submitPassword()
      onToggleShowRequested: root.showPw = !root.showPw
      onPickUserRequested: (index) => backend.pickUser(index)
      onSessionStepRequested: (delta) => backend.sessionStep(delta)
      onPowerRequested: (action) => root.armOrFirePower(action)
    }
  }
}

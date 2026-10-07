import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import QtQuick

import "./polkit"
import "./widgets"

// ===== POLKIT AUTHENTICATION AGENT =====
// Replaces polkit-kde-authentication-agent-1: owns the one PolkitAgent
// (registers on the system bus for this login session -- only one agent can
// per session, so the KDE one must not also be running), shows each request
// in PolkitDialog on an Overlay window with exclusive keyboard focus, and
// reports the outcome in a toast.
//
// What the API gives us: message, actionId, identities, the PAM prompt and
// info/error text, and success/failure. It does NOT give the calling app or
// process, so the mockup's "app" line and caller details aren't shown.
// Fingerprint (fprintd) arrives as plain PAM info/error text, so it's
// recognised by "finger" in that text; PAM asks for the password only after
// the fingerprint attempt ends, hence the big sensor view first, then the
// password box with a compact sensor beside it.
Scope {
  id: root

  PolkitAgent { id: agent }
  readonly property var flow: agent.flow

  property bool active: false
  property bool done: false
  property string phase: "input"
  property var targetScreen: null

  // snapshot of the request (the flow may go away right after it completes)
  property string message: ""
  property string actionId: ""
  property string iconName: ""
  property var identities: []
  property int identityIndex: 0

  property bool fpSeen: false
  property string fpState: "none"

  readonly property string currentUser: Quickshell.env("USER") || ""

  // ----- request presentation -----
  readonly property var category: {
    const a = actionId;
    if (/NetworkManager/i.test(a)) return { glyph: "wifi-high", tone: Pal.blue, via: "NetworkManager" };
    if (a === "org.freedesktop.policykit.exec") return { glyph: "package", tone: Pal.yellow, via: "pkexec" };
    if (/udisks2/i.test(a)) return { glyph: "hard-drives", tone: Pal.green, via: "udisksd" };
    if (/systemd1|login1|timedate1|hostname1|locale1/i.test(a)) {
      const m = /org\.freedesktop\.([a-z]+)/i.exec(a);
      return { glyph: "gear-six", tone: Pal.purple, via: m ? m[1] : "systemd" };
    }
    const parts = a.split(".");
    return { glyph: "lock-simple", tone: Pal.blue, via: parts.length > 2 ? parts[2] : "polkit" };
  }
  // "Authentication is required to mount X." -> "mount X" for the toast
  function shortOf(msg) {
    const q = /`([^']*)'/.exec(msg);
    if (q) return q[1];
    let s = msg.replace(/^Authentication (is )?(required|needed) (to|for) /i, "").replace(/[.\s]+$/, "");
    return s.length > 44 ? s.slice(0, 43) + "…" : s;
  }

  function resolveFocusedScreen() {
    const mon = Hyprland.focusedMonitor;
    if (mon) for (const s of Quickshell.screens) if (s.name === mon.name) return s;
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }

  function readIdentities() {
    const f = flow;
    if (!f) return;
    const out = [];
    let sel = 0;
    for (let i = 0; i < f.identities.length; i++) {
      const id = f.identities[i];
      // `string` is the login name; `displayName` is the capitalised full name
      out.push({ label: id.string, note: !id.isGroup && id.string === currentUser ? "(you)" : "" });
      if (f.selectedIdentity === id) sel = i;
    }
    identities = out;
    identityIndex = sel;
  }

  function begin() {
    const f = flow;
    if (!f) return;
    done = false;
    phase = "input";
    fpSeen = false;
    fpState = "none";
    toast.shown = false;
    message = f.message;
    actionId = f.actionId;
    iconName = f.iconName;
    targetScreen = resolveFocusedScreen();
    dialog.reset();
    dialog.errorText = "";
    readIdentities();
    active = true;
    Qt.callLater(dialog.focusInput);
    handleInfo();
  }

  function showToast(kind, title) {
    toast.kind = kind;
    toast.title = title;
    toast.sub = shortOf(message);
    toast.screen = targetScreen;
    toast.shown = true;
    toastTimer.restart();
  }

  function succeed() {
    if (done) return;
    done = true;
    phase = "success";
    if (fpSeen && fpState !== "out") fpState = "match";
    closeTimer.restart();
  }
  function complete() {
    if (done || !flow) return;
    if (flow.isSuccessful) { succeed(); return; }
    done = true;
    active = false;
    showToast(flow.isCancelled ? "cancel" : "fail", flow.isCancelled ? "request dismissed" : "authentication failed");
  }
  function cancel() {
    if (done) return;
    done = true;
    if (flow) flow.cancelAuthenticationRequest();
    active = false;
    showToast("cancel", "request dismissed");
  }
  function submit(pw) {
    if (done || !flow || phase !== "input") return;
    phase = "verifying";
    flow.submit(pw);
  }
  function cycleIdentity() {
    if (!flow || identities.length < 2 || phase !== "input") return;
    flow.selectedIdentity = flow.identities[(identityIndex + 1) % identities.length];
    dialog.clearInput();
    dialog.errorText = "";
  }

  // fprintd talks through PAM info/error text
  function handleInfo() {
    const f = flow;
    if (!f) return;
    const msg = f.supplementaryMessage || "";
    if (msg === "") return;
    const isFp = /finger/i.test(msg);
    if (isFp) fpSeen = true;
    if (fpSeen && (isFp || f.supplementaryIsError)) {
      if (f.supplementaryIsError) {
        fpState = "nomatch";
        dialog.shake();
        fpRevert.restart();
      } else {
        fpState = "listening";
      }
    } else if (f.supplementaryIsError && dialog.errorText === "") {
      dialog.errorText = msg;
    }
  }

  Connections {
    target: agent
    function onAuthenticationRequestStarted() { root.begin(); }
  }
  Connections {
    target: root.flow
    ignoreUnknownSignals: true
    function onIsResponseRequiredChanged() {
      if (root.done) return;
      if (!root.flow.isResponseRequired) {
        // conversation restarting (e.g. after a wrong password): sensor is live again
        if (root.fpSeen) root.fpState = "listening";
        return;
      }
      root.phase = "input";
      if (root.fpSeen) root.fpState = "out";
      Qt.callLater(dialog.focusInput);
    }
    function onSupplementaryMessageChanged() { root.handleInfo(); }
    function onAuthenticationFailed() {
      if (root.done) return;
      root.phase = "input";
      dialog.errorText = "sorry, try again.";
      dialog.clearInput();
      dialog.shake();
      Qt.callLater(dialog.focusInput);
    }
    function onAuthenticationSucceeded() { root.succeed(); }
    function onIsCompletedChanged() { if (root.flow.isCompleted) root.complete(); }
    function onAuthenticationRequestCancelled() { root.complete(); }
    function onSelectedIdentityChanged() { root.readIdentities(); }
  }

  Timer { id: fpRevert; interval: 1300; onTriggered: if (root.fpState === "nomatch") root.fpState = (root.flow && root.flow.isResponseRequired) ? "out" : "listening" }
  // let "authorized" show for a beat before the dialog goes
  Timer {
    id: closeTimer
    interval: 850
    onTriggered: { root.active = false; root.showToast("ok", "authorized"); }
  }
  Timer { id: toastTimer; interval: 4000; onTriggered: toast.shown = false }

  PanelWindow {
    id: win
    screen: root.targetScreen
    visible: root.active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "coel-polkit"

    PolkitDialog {
      id: dialog
      anchors.fill: parent
      message: root.message
      actionId: root.actionId
      iconName: root.iconName
      via: root.category.via
      glyph: root.category.glyph
      tone: root.category.tone
      identities: root.identities
      identityIndex: root.identityIndex
      phase: root.phase
      responseRequired: root.flow ? root.flow.isResponseRequired : false
      prompt: root.flow ? root.flow.inputPrompt : ""
      echo: root.flow ? root.flow.responseVisible : false
      fpState: root.fpState
      fpSeen: root.fpSeen
      detailRows: [["action", root.actionId], ["identity", root.identities.length ? root.identities[root.identityIndex].label : ""]]
        .concat(root.iconName !== "" ? [["icon", root.iconName]] : [])
      onSubmitted: (pw) => root.submit(pw)
      onCancelled: root.cancel()
      onCycleIdentity: root.cycleIdentity()
    }
  }

  PolkitToast { id: toast }
}

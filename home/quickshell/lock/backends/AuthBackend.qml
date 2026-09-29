import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import QtQuick

// ===== AUTH BACKEND =====
// Real password + fingerprint auth for the lock screen, via Quickshell's
// own native Quickshell.Services.Pam (PamContext) against two dedicated,
// single-purpose PAM services declared in configuration.nix:
// `quickshell-lock` (password/pam_unix only) and `quickshell-lock-fp`
// (fingerprint/pam_fprintd only). Deliberately two independent stacks
// mirroring hyprlock's own CPam/CFingerprint split (see configuration.nix's
// comments on hyprlock/login) rather than one shared stack with both
// modules -- a shared stack has the exact "password waits on the
// fingerprint conversation" ordering bug already fixed there twice; two
// stacks with one module each sidesteps the ordering question entirely.
//
// Previously shelled out to `pamtester` on the (wrong) belief that no
// QML-native PAM binding existed -- confirmed live it does
// (Quickshell.Services.Pam.PamContext), so this is a straight upgrade: no
// subprocess, no stdin-write timing, and PamContext's onMessage callback
// genuinely supports arbitrary multi-step PAM conversations (not just "read
// one line"), which the greeter work will also depend on.
//
// Fingerprint listening is continuous, not click-triggered -- per explicit
// request, matching real hyprlock's own always-on native fingerprint
// backend (which "genuinely runs in parallel", see configuration.nix's
// comment on it) rather than something the user has to remember to start.
// `fingerprintEnrolled` (real, via `fprintd-list` -- no native Quickshell
// service exists for fprintd itself, only Pam/Greetd/Mpris/etc., so this
// one piece still shells out) is what the lock screen's fingerprint icon
// actually reflects -- a passive "is this even available" indicator, not
// a button.
//
// Only ever checks the real, current session user -- there's no real
// multi-user backend (that's future greetd/login work, still a login-mode-
// only demo in Lock.qml), and a lock screen shouldn't offer to unlock as
// someone else regardless.
//
// Both result signals carry a diagnostic string alongside success/failure
// (PamResult/PamError's own toString()) -- a genuine backend problem (the
// PAM service missing/misconfigured) and a plain wrong password/failed
// verify both need to be tellable apart. Collapsing both into one generic
// failure is exactly what left a previous real-mode test stuck with
// password entry that could never succeed and no indication why, forcing
// a hard reboot to escape.
Item {
  id: root

  readonly property string username: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

  signal passwordResult(bool success, string error)
  signal fingerprintResult(bool success, string error)

  // ----- password -----
  PamContext {
    id: pwPam
    config: "quickshell-lock"
    user: root.username
    property string pendingPw: ""

    // `onMessage` in the qmltypes dump isn't backed by an actual signal
    // (qmllint confirmed: "no matching signal found" when written as a
    // signal handler) -- the real signal is the parameterless `pamMessage`,
    // with the message/responseRequired/etc. properties already updated to
    // reflect it by the time this fires.
    onPamMessage: {
      if (responseRequired) {
        respond(pendingPw);
        pendingPw = "";
      }
    }
    onCompleted: (result) => {
      const success = result === PamResult.Success;
      // Failed = the conversation ran to completion and PAM just said no --
      // a routine wrong password, not a backend problem, so no diagnostic
      // text (empty string is Lock.qml's signal for "ordinary failure").
      // Error/MaxTries completing is unusual enough to surface as-is.
      const detail = success || result === PamResult.Failed ? "" : PamResult.toString(result);
      root.passwordResult(success, detail);
    }
    onError: (error) => root.passwordResult(false, PamError.toString(error))
  }
  function checkPassword(pw) {
    if (pwPam.active) return;
    pwPam.pendingPw = pw;
    pwPam.start();
  }

  // ----- fingerprint enrollment -----
  property string enrollListText: ""
  readonly property bool fingerprintEnrolled: enrollListText.indexOf(" - #") !== -1
  Process {
    id: enrollProc
    command: ["fprintd-list", root.username]
    stdout: StdioCollector {
      onStreamFinished: {
        root.enrollListText = text;
        if (root.fingerprintEnrolled) fpPam.start();
      }
    }
  }
  Component.onCompleted: enrollProc.running = true

  // ----- fingerprint verification, continuous -----
  // Always listening once enrollment is confirmed, for the whole lifetime
  // of this Item -- not started/stopped by anything else. A single
  // PamContext conversation already retries a failed swipe internally a
  // few times before actually completing; once it does (match or not),
  // this just restarts it after a short debounce so it's always available
  // again, rather than requiring a click to re-arm. Only restarts on
  // failure -- a success means the lock screen is tearing down right
  // after anyway (see Lock.qml's succeedAuth()), so there's nothing left
  // to listen for.
  PamContext {
    id: fpPam
    config: "quickshell-lock-fp"
    user: root.username
    onCompleted: (result) => {
      const success = result === PamResult.Success;
      // Same "Failed is routine, anything else is worth surfacing" split
      // as the password PamContext above.
      const detail = success || result === PamResult.Failed ? "" : PamResult.toString(result);
      root.fingerprintResult(success, detail);
      if (!success) fpRestartTimer.restart();
    }
    onError: (error) => {
      root.fingerprintResult(false, PamError.toString(error));
      fpRestartTimer.restart();
    }
  }
  // Debounced, not an immediate restart -- a hard-broken backend (e.g. the
  // PAM service missing) would otherwise complete near-instantly forever,
  // busy-looping for no benefit.
  Timer { id: fpRestartTimer; interval: 400; onTriggered: fpPam.start() }
}

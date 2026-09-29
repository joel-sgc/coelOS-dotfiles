import Quickshell
import Quickshell.Io
import QtQuick

// ===== AUTH BACKEND =====
// Real password + fingerprint auth for the lock screen, via `pamtester`
// (nixpkgs' pamtester, added to home/quickshell.nix) against two
// dedicated, single-purpose PAM services declared in configuration.nix:
// `quickshell-lock` (password/pam_unix only) and `quickshell-lock-fp`
// (fingerprint/pam_fprintd only). Deliberately two independent stacks
// mirroring hyprlock's own CPam/CFingerprint split (see configuration.nix's
// comments on hyprlock/login) rather than one shared stack with both
// modules -- a shared stack has the exact "password waits on the
// fingerprint conversation" ordering bug already fixed there twice; two
// stacks with one module each sidesteps the ordering question entirely.
//
// Fingerprint listening is continuous, not click-triggered -- per explicit
// request, matching real hyprlock's own always-on native fingerprint
// backend (which "genuinely runs in parallel", see configuration.nix's
// comment on it) rather than something the user has to remember to start.
// `fingerprintEnrolled` (real, via `fprintd-list`) is what the lock
// screen's fingerprint icon actually reflects now -- a passive "is this
// even available" indicator, not a button.
//
// Only ever checks the real, current session user -- there's no real
// multi-user backend (that's future greetd/login work, still a login-mode-
// only demo in Lock.qml), and a lock screen shouldn't offer to unlock as
// someone else regardless.
//
// Both result signals carry pamtester's own stderr text alongside
// success/failure -- confirmed live that a genuine backend problem (the
// PAM service not existing yet, before a NixOS switch) and a plain wrong
// password/failed verify both exit non-zero with no other distinction
// available, but pamtester's stderr differs ("Initialization failure" vs.
// "Permission denied"). Lock.qml uses that text to tell "no match" apart
// from "the backend itself is broken" -- collapsing both into one generic
// failure is exactly what left a previous real-mode test stuck with
// password entry that could never succeed and no indication why, forcing
// a hard reboot to escape.
Item {
  id: root

  readonly property string username: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

  signal passwordResult(bool success, string error)
  signal fingerprintResult(bool success, string error)

  Process {
    id: pwProc
    stdinEnabled: true
    property string pendingPw: ""
    property string errText: ""
    command: ["pamtester", "quickshell-lock", root.username, "authenticate"]
    stderr: StdioCollector {
      onStreamFinished: pwProc.errText = text.trim()
    }
    onStarted: {
      write(pendingPw + "\n");
      pendingPw = "";
    }
    onExited: (exitCode, exitStatus) => root.passwordResult(exitCode === 0, pwProc.errText)
  }
  function checkPassword(pw) {
    if (pwProc.running) return;
    pwProc.pendingPw = pw;
    pwProc.running = true;
  }

  // ----- fingerprint enrollment (real, via fprintd-list) -----
  property string enrollListText: ""
  readonly property bool fingerprintEnrolled: enrollListText.indexOf(" - #") !== -1
  Process {
    id: enrollProc
    command: ["fprintd-list", root.username]
    stdout: StdioCollector {
      onStreamFinished: {
        root.enrollListText = text;
        if (root.fingerprintEnrolled) fpProc.running = true;
      }
    }
  }
  Component.onCompleted: enrollProc.running = true

  // ----- fingerprint verification, continuous -----
  // Always listening once enrollment is confirmed, for the whole lifetime
  // of this Item -- not started/stopped by anything else. A single
  // pamtester/pam_fprintd call already retries a failed swipe internally a
  // few times before actually exiting; once it does exit (match or not),
  // this just restarts it after a short debounce so it's always available
  // again, rather than requiring a click to re-arm.
  Process {
    id: fpProc
    property string errText: ""
    command: ["pamtester", "quickshell-lock-fp", root.username, "authenticate"]
    stderr: StdioCollector {
      onStreamFinished: fpProc.errText = text.trim()
    }
    onExited: (exitCode, exitStatus) => {
      root.fingerprintResult(exitCode === 0, fpProc.errText);
      if (exitCode !== 0) fpRestartTimer.restart();
    }
  }
  // Debounced, not an immediate restart -- a hard-broken backend (e.g. the
  // PAM service missing) would otherwise exit near-instantly forever,
  // busy-looping pamtester/dbus calls for no benefit.
  Timer { id: fpRestartTimer; interval: 400; onTriggered: fpProc.running = true }
}

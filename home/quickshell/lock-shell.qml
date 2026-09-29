import Quickshell

import "./lock"

// ===== LOCK SCREEN TEST HARNESS =====
// Standalone entry point for this pass -- launch with
// `quickshell -p ~/.nixos/home/quickshell/lock-shell.qml`, a different
// process from the live production panel (which loads shell.qml, right
// next to this file, as its own default config), safe to pkill/relaunch
// freely. Never wired into the real shell.qml this pass; see Lock.qml's
// own comment for why (plain PanelWindow, not a real WlSessionLock, until
// a later, separately sign-off'd pass).
//
// Lives here at the quickshell config root rather than inside lock/
// itself: quickshell sandboxes each config to its own root directory
// (confirmed live -- a relative import from inside lock/ trying to reach
// up to ../../sysPanel/Phosphor.js got refused as "qrc:/qs-blackhole"),
// so the entry file has to sit at the same root as sysPanel/ and assets/
// for lock/'s existing relative imports into both to resolve at all.
ShellRoot {
  Lock {}
}

import Quickshell

import "./lock"

// ===== REAL LOCK SCREEN =====
// The actual production entry point -- home/hypridle.nix's lock_cmd/
// before_sleep_cmd/idle listener and home/hyprland.nix's $mainMod+L bind
// all launch this (via the home-manager-deployed
// ~/.config/quickshell/lock-real-shell.qml path, not this repo path --
// see hypridle.nix's own comment for why). `real: true` switches Lock.qml
// over to its genuine WlSessionLock/WlSessionLockSurface branch (real
// ext-session-lock-v1, real PAM auth via lock/backends/AuthBackend.qml,
// real systemctl on a confirmed power action) instead of lock-shell.qml's
// plain-PanelWindow dev harness.
//
// Lives at the config root next to shell.qml/lock-shell.qml for the same
// reason lock-shell.qml does: quickshell sandboxes each config to its own
// root directory, and lock/'s existing relative imports into sysPanel/ and
// assets/ need to stay inside that root.
ShellRoot {
  Lock { real: true }
}

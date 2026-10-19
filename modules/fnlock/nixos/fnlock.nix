# Fn lock detection for a Framework 13 (AMD 7040) running the patched EC.
# Import from your configuration.nix:  imports = [ ./path/to/fw13-fnlock/nixos/fnlock.nix ];
{ pkgs, ... }:
{
  # No hwdb remap here: the patched EC's F13/F14 taps already arrive as
  # distinct keys (xkb names them XF86Tools / XF86Launch5), which
  # home/hyprland.nix binds to the Quickshell OSD. A KEY_PROG3/4 remap would
  # change the keycodes and silently break those binds.

  # Root service that keeps /run/fnlock/state ("locked"/"unlocked") current,
  # so bars and scripts can read it without root.
  systemd.services.fnlockd = {
    description = "Track Framework Fn lock state";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${../fnlock-state.py} --watch --state-file /run/fnlock/state";
      RuntimeDirectory = "fnlock";
      Restart = "always";
      RestartSec = 5;
    };
  };
}

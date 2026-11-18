{
  lib,
  pkgs,
  config,
  ...
}:

let
  theme = import ./theme/onedark.nix;
  strip = lib.removePrefix "#";

  # The real Quickshell-based lock screen (home/quickshell/lock/), replacing
  # hyprlock -- see programs.hyprlock's own comment below for why hyprlock's
  # config is left in place, unused, as a manual fallback rather than
  # removed.
  #
  # Points at the live repo path, same convention as home/hyprland.nix's
  # exec-once for the bar -- the home-manager-deployed config path
  # (~/.config/quickshell/) only refreshes on an actual switch, so it can
  # silently point at a stale pre-lock-screen generation. Trade-off: an
  # in-progress edit here would hot-reload into a real, currently-held
  # session lock -- don't edit lock/*.qml while actually locked.
  #
  # `coel-hub lock` (modules/session-hub.nix) locks this session, then goes to
  # the login screen -- only if this session is the one on screen, so an idle
  # session in the background is locked but never pulls you away from the one
  # you are using. The Quickshell lock screen itself is still the in-session
  # lock (started by coel-hub).
  lockCmd = "/run/current-system/sw/bin/coel-hub lock";

  # Last resort only. Normally the lock has already gone to the login screen,
  # which blanks and suspends the machine itself (modules/session-hub.nix).
  # This one suspends only if THIS session is still the one on screen (locked
  # in place because the login screen is not running); with the login screen or
  # another session on screen it does nothing, so a session in the background
  # never suspends the machine while someone is using another.
  suspendCmd = "/run/current-system/sw/bin/coel-hub suspend-fallback";
in
{
  # Idle + lock screen. The three timeouts (lock / screen off / suspend) are not
  # set here: they live in settings.toml's [idle] table (repo root) so they can
  # be changed without a rebuild. This unit renders hypridle's config from that
  # file each time it starts (`coel-settings render-hypridle`); `coel-settings
  # apply` restarts it when the [idle] values changed. Defaults, used when the
  # file or a key is missing (and for the guest account, which has no
  # settings.toml): 10 min -> lock, 15 -> screen off, 20 -> suspend.
  #
  # Scoped to hyprland-session.target via home/hyprland.nix's
  # wayland.systemd.target, so this only runs during a Hyprland session.
  # (Replaces home-manager's services.hypridle, which can only ship a fixed
  # config file from the Nix store.)
  systemd.user.services.hypridle =
    let
      dpms = state: "hyprctl dispatch 'hl.dsp.dpms({ action = \"${state}\" })'";
      run = pkgs.writeShellScript "hypridle-run" ''
        conf="''${XDG_RUNTIME_DIR:-/tmp}/hypridle.conf"
        ${pkgs.python3}/bin/python3 ${./settings/coel_settings.py} render-hypridle \
          --out "$conf" \
          --lock-cmd ${lib.escapeShellArg lockCmd} \
          --suspend-cmd ${lib.escapeShellArg suspendCmd} \
          --dpms-on-cmd ${lib.escapeShellArg (dpms "on")} \
          --dpms-off-cmd ${lib.escapeShellArg (dpms "off")}
        exec ${pkgs.hypridle}/bin/hypridle -c "$conf"
      '';
    in
    {
      Install.WantedBy = [ config.wayland.systemd.target ];
      Unit = {
        ConditionEnvironment = "WAYLAND_DISPLAY";
        Description = "hypridle";
        After = [ config.wayland.systemd.target ];
        PartOf = [ config.wayland.systemd.target ];
        # Rebuilds that change this script restart the service; settings.toml
        # edits do not need that (see above).
        X-Restart-Triggers = [ "${run}" ];
      };
      Service = {
        ExecStart = "${run}";
        Restart = "always";
        RestartSec = "10";
      };
    };

  # No longer wired to lock_cmd/before_sleep_cmd/the idle listener above (or
  # the $mainMod+L keybind in home/hyprland.nix) -- all three now point at
  # the real Quickshell lock screen instead. Left enabled here anyway as a
  # real, independent manual fallback (`hyprlock` still works standalone if
  # the new one ever regresses); revisit removing this once Quickshell's
  # lock has been the daily driver for a while.
  #
  # Requires security.pam.services.hyprlock in configuration.nix for the
  # password prompt to authenticate -- see that file's comment on why
  # `fprintAuth = false` there: hyprlock has two independent auth backends
  # (Pam and Fingerprint), each unlocking on its own success.
  # `auth.fingerprint.enabled` below turns on hyprlock's own native one.
  programs.hyprlock = {
    enable = true;
    settings = {
      auth = {
        pam.enabled = true;
        fingerprint.enabled = true;
      };

      background.color = "rgba(${strip theme.bg}ee)";
      "input-field" = {
        outer_color = "rgb(${strip theme.blue})";
        inner_color = "rgba(${strip theme.bg}cc)";
        font_color = "rgb(${strip theme.fg})";
      };

      # The "COEL OS" wordmark, same asset used for the Plymouth boot
      # splash (../coelos-theme/logo.png) -- positioned above the input
      # field. Position is a starting guess (up from center), adjust to
      # taste.
      image = [
        {
          path = "${../assets/plymouth-theme/logo.png}";
          size = 300;
          border_size = 0;
          rounding = 0;
          halign = "center";
          valign = "center";
          position = "0, 200";
        }
      ];
    };
  };
}

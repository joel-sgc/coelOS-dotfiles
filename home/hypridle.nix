{ lib, ... }:

let
  theme = import ./theme/onedark.nix;
  strip = lib.removePrefix "#";

  # The real Quickshell-based lock screen (home/quickshell/lock/), replacing
  # hyprlock -- see programs.hyprlock's own comment below for why hyprlock's
  # config is left in place, unused, as a manual fallback rather than
  # removed.
  #
  # Points at the live repo path, same convention home/hyprland.nix's own
  # exec-once already uses for the bar -- confirmed live that the
  # home-manager-*deployed* config path (~/.config/quickshell/) doesn't
  # reliably have this file: the deployed ~/.config/quickshell symlink
  # target only refreshes on an actual switch, and in testing it pointed at
  # a generation from well before this lock-screen work existed, causing
  # both this and the $mainMod+L bind to silently fail against a
  # nonexistent file. The repo path is always current. Trade-off accepted:
  # an in-progress edit here would hot-reload into a *real*, currently-held
  # session lock, unlike the bar, which wants that hot-reload live while
  # developing it -- just don't edit lock/*.qml while actually locked.
  lockCmd = "quickshell -p ~/.nixos/home/quickshell/lock-real-shell.qml";
in
{
  # Idle + lock screen. Timings match the old Arch/Omarchy setup:
  # 5min -> lock, 10min -> screen off, 20min -> suspend.
  #
  # Scoped to hyprland-session.target via home/hyprland.nix's
  # wayland.systemd.target, so this never runs during a Plasma session.
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = lockCmd;
        before_sleep_cmd = lockCmd;
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = 600;
          on-timeout = lockCmd;
        }
        {
          timeout = 900;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1200;
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  # No longer wired to lock_cmd/before_sleep_cmd/the idle listener above (or
  # to the $mainMod+L keybind in home/hyprland.nix) -- all three now point
  # at the real Quickshell lock screen instead. Left enabled and configured
  # here anyway, deliberately not removed: it's a real, independent manual
  # fallback (`hyprlock` still works standalone, PAM and all, if the new
  # one ever regresses) exactly while that's still new. Revisit removing
  # this once the Quickshell lock has been the daily driver for a while.
  #
  # Requires security.pam.services.hyprlock in configuration.nix for the
  # password prompt to actually authenticate. That same file also sets
  # `fprintAuth = false` for this service specifically -- see the comment
  # there for why: hyprlock has two genuinely independent auth backends
  # (src/auth/{Pam,Fingerprint}.cpp, confirmed straight from its source),
  # each unlocking on its own success with no dependency on the other.
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
          path = "${../coelos-theme/logo.png}";
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

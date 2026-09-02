{ lib, ... }:

let
  theme = import ./theme/onedark.nix;
  strip = lib.removePrefix "#";
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
        lock_cmd = "hyprlock";
        before_sleep_cmd = "hyprlock";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = 300;
          on-timeout = "hyprlock";
        }
        {
          timeout = 600;
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

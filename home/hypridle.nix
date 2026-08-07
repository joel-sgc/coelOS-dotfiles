{ config, pkgs, ... }:

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

  # No visual config yet (defaults render a plain lock screen) — theming
  # comes later. Requires security.pam.services.hyprlock in configuration.nix
  # for the password prompt to actually authenticate.
  programs.hyprlock.enable = true;
}

{ config, pkgs, lib, ... }:

{
  # Automounts removable media (USB drives, SD cards) under Hyprland.
  # Plasma doesn't need this -- Dolphin/its own device-notifier already
  # handle automount there -- which is exactly why this can't be left at
  # its defaults.
  services.udiskie = {
    enable = true;
    # "auto" (the default) makes udiskie Require a tray.target that only
    # becomes active once a systray exists. Waybar doesn't have a tray
    # module configured yet, so automount would silently never start.
    # Revisit once waybar's tray module lands.
    tray = "never";
  };

  # udiskie's own module hardcodes graphical-session.target rather than
  # respecting wayland.systemd.target the way hypridle/awww/swayosd/cliphist
  # do (see home/hyprland.nix) -- overridden here so it doesn't also start
  # under Plasma, which already handles automount on its own.
  systemd.user.services.udiskie = {
    Unit = {
      After = lib.mkForce [ config.wayland.systemd.target ];
      PartOf = lib.mkForce [ config.wayland.systemd.target ];
    };
    Install.WantedBy = lib.mkForce [ config.wayland.systemd.target ];
  };
}

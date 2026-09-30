{ config, lib, ... }:

{
  # Automounts removable media (USB drives, SD cards) under Hyprland.
  # Plasma doesn't need this -- Dolphin/its own device-notifier already
  # handle automount there -- which is exactly why this can't be left at
  # its defaults.
  services.udiskie = {
    enable = true;
    # "auto" (the default) makes udiskie Require a tray.target that only
    # becomes active once a systray exists and registers as a
    # StatusNotifierWatcher. Not yet confirmed whether the Quickshell
    # panel's own tray (sysPanel/buttons/Tray.qml) does that, so left off
    # rather than risk automount silently never starting.
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

{ config, pkgs, lib, ... }:

{
  # Battery/power notifications (low battery, charger plugged/unplugged) --
  # a full DE provides this for free (Plasma's own power applet watches
  # UPower and notifies), a bare Hyprland setup has nothing filling that
  # role without this. Found by cross-referencing HyDE's package list,
  # which includes it as a baseline utility, not an extra.
  services.poweralertd.enable = true;
  # This Framework laptop exposes its one real charger as *two* separate
  # UPower line-power devices (native paths "ACAD" and
  # "ucsi-source-psy-USBC000:004") -- confirmed live via dbus-monitor:
  # every plug/unplug fires three separate poweralertd Notify calls, one
  # per line-power device plus one for the battery's own charging/
  # discharging transition, all for the same single physical event.
  # "-i line power" drops both line-power alerts, leaving just the
  # battery one ("Battery charging/discharging, current level: N%"),
  # which already conveys plug state plus a number the bare line-power
  # alerts didn't have. Low-battery warnings are a *different* message
  # from the same "battery" device type, so they're unaffected -- only
  # "line power" is excluded, not "battery".
  services.poweralertd.extraArgs = [ "-i" "line power" ];

  # Same fix as home/udiskie.nix: this module hardcodes
  # graphical-session.target rather than respecting wayland.systemd.target,
  # so left alone it would also start under Plasma.
  systemd.user.services.poweralertd = {
    Unit = {
      After = lib.mkForce [ config.wayland.systemd.target ];
      PartOf = lib.mkForce [ config.wayland.systemd.target ];
    };
    Install.WantedBy = lib.mkForce [ config.wayland.systemd.target ];
  };
}

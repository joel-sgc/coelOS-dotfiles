{ config, pkgs, lib, ... }:

{
  # Battery/power notifications (low battery, charger plugged/unplugged) --
  # a full DE provides this for free (Plasma's own power applet watches
  # UPower and notifies), a bare Hyprland setup has nothing filling that
  # role without this. Found by cross-referencing HyDE's package list,
  # which includes it as a baseline utility, not an extra.
  services.poweralertd.enable = true;

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

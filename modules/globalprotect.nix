{ config, pkgs, lib, ... }:

let
  gpVendor = pkgs.runCommand "globalprotect-vendor" {} ''
    mkdir -p $out
    cp -r ${./vendor/opt/paloaltonetworks/globalprotect}/* $out/
  '';

  gpFHS = (import ../lib/globalprotect-fhs.nix { inherit pkgs; }) "globalprotect-fhs";

  # GlobalProtect's full-tunnel config duplicates routes for whatever local
  # subnet you're actually on through its own tunnel interface (gpd0), with
  # no explicit metric (defaults to 0), beating the real route -- breaks
  # SSH/DNS/anything else on that subnet while connected. Confirmed on a
  # test VM and on this host itself (see globalprotect-hip-investigation.md).
  # PanGPS has a netlink-reactive watchdog that re-adds a plainly-deleted
  # route within milliseconds, so this bypasses it with policy routing
  # instead of fighting it: finds every subnet routed via *both* gpd0 and a
  # different device (that pairing is the hijack signature, regardless of
  # which specific subnet/network you're on) and routes it through a
  # separate table that PanGPS has no reason to touch.
  gpRouteFix = pkgs.writeShellApplication {
    name = "gp-route-fix";
    runtimeInputs = [ pkgs.iproute2 pkgs.jq pkgs.gnugrep ];
    text = builtins.readFile ./globalprotect/gp-route-fix.sh;
  };
in
{
  environment.systemPackages = [ gpFHS gpRouteFix ];

  systemd.services.gp-route-fix-up = {
    description = "Bypass GlobalProtect's local-subnet route hijack";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gpRouteFix}/bin/gp-route-fix up";
    };
  };

  systemd.services.gp-route-fix-down = {
    description = "Clean up GlobalProtect route-hijack bypass";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gpRouteFix}/bin/gp-route-fix down";
    };
  };

  # Triggers off the actual kernel event of gpd0 appearing/disappearing,
  # rather than a NetworkManager dispatcher script -- NM never manages or
  # notices gpd0 (PanGPS brings it up directly, outside NM entirely), so a
  # dispatcher hook wouldn't reliably fire for it.
  services.udev.extraRules = ''
    SUBSYSTEM=="net", KERNEL=="gpd0", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}="gp-route-fix-up.service"
    SUBSYSTEM=="net", KERNEL=="gpd0", ACTION=="remove", TAG+="systemd", ENV{SYSTEMD_WANTS}="gp-route-fix-down.service"
  '';

  users.groups.globalprotect = {};

  systemd.tmpfiles.rules = [
    "d /var/lib/globalprotect 0775 root globalprotect -"
  ];

  systemd.services.globalprotect-daemon = {
    description = "GlobalProtect VPN client daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = [
        "-${pkgs.coreutils}/bin/rm -f /var/run/PanGPS.pid"
        "${pkgs.rsync}/bin/rsync -a --chmod=Du=rwx,Fu=rw ${gpVendor}/ /var/lib/globalprotect/"
        "${pkgs.coreutils}/bin/chgrp -R globalprotect /var/lib/globalprotect"
        "${pkgs.coreutils}/bin/chmod -R g+w /var/lib/globalprotect"
      ];
      ExecStart = "${gpFHS}/bin/globalprotect-fhs -c 'cd /opt/paloaltonetworks/globalprotect && ./PanGPS'";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}

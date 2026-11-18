{ config, pkgs, pkgs-pinned, lib, ... }:

let
  gpVendor = pkgs.runCommand "globalprotect-vendor" {} ''
    mkdir -p $out
    cp -r ${./globalprotect/vendor/opt/paloaltonetworks/globalprotect}/* $out/
  '';

  gpFHS = (import ./globalprotect/fhs.nix { pkgs = pkgs-pinned; }) "globalprotect-fhs";

  # Ranges that must go through GlobalProtect even while Tailscale has an
  # exit node (see globalprotect/vpn-routes.sh for the rule ladder). GP here is
  # a pure full tunnel with no pushed route list, so LUC's networks are
  # declared by hand. 147.126.0.0/16 is LUC's public block (IP-gated library
  # resources etc.); the gateway's own /32 is exempted automatically.
  gpRanges = [ "10.0.0.0/8" "147.126.0.0/16" ];

  vpnRoutes = pkgs.writeShellApplication {
    name = "coel-vpn-routes";
    runtimeInputs = [ pkgs.iproute2 pkgs.jq pkgs.gnugrep pkgs.coreutils ];
    text = "export GP_RANGES=\"${lib.concatStringsSep " " gpRanges}\"\n" + builtins.readFile ./globalprotect/vpn-routes.sh;
  };
in
{
  environment.systemPackages = [ gpFHS vpnRoutes ];

  # Long-running reconciler: re-applies the rule ladder whenever links,
  # addresses or routes change (gpd0 / tailscale0 / wifi coming and going).
  # Replaces the old one-shot udev-triggered gp-route-fix, which only fired
  # when gpd0 was *created* -- but PanGPS keeps gpd0 around, so connecting
  # later never re-ran it.
  systemd.services.coel-vpn-routes = {
    description = "Reconcile Tailscale / GlobalProtect / LAN policy routing";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${vpnRoutes}/bin/coel-vpn-routes watch";
      ExecStopPost = "${vpnRoutes}/bin/coel-vpn-routes down";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  users.groups.globalprotect = {};

  systemd.tmpfiles.rules = [
    "d /var/lib/globalprotect 0775 root globalprotect -"

    # Real host mountpoint the FHS sandboxes bind /var/lib/globalprotect
    # onto. It predates this NixOS module (leftover from GlobalProtect's
    # original native install, root:root 0700), and bwrap has to mkdir its
    # own mountpoint inside it as whichever user runs the sandbox -- that
    # succeeds for the root daemon but fails for the per-user agent with
    # "Permission denied". Same root:globalprotect 0775 treatment as
    # /var/lib/globalprotect above fixes it.
    "d /opt/paloaltonetworks 0775 root globalprotect -"
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

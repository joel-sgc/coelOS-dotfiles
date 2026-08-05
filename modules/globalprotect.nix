{ config, pkgs, lib, ... }:

let
  gpVendor = pkgs.runCommand "globalprotect-vendor" {} ''
    mkdir -p $out
    cp -r ${./vendor/opt/paloaltonetworks/globalprotect}/* $out/
  '';

  gpFHS = (import ../lib/globalprotect-fhs.nix { inherit pkgs; }) "globalprotect-fhs";
in
{
  environment.systemPackages = [ gpFHS ];

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

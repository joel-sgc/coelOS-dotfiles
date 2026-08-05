{ config, pkgs, lib, ... }:

let
  gpFHS = (import ../lib/globalprotect-fhs.nix { inherit pkgs; }) "globalprotect-agent-fhs";
in
{
  systemd.user.services.globalprotect-agent = {
    Unit.Description = "GlobalProtect VPN client Agent";
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${gpFHS}/bin/globalprotect-agent-fhs -c 'cd /opt/paloaltonetworks/globalprotect && ./PanGPA start'";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };
}

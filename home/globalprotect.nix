{ config, pkgs, lib, ... }:

let
  gpFHS = (import ../lib/globalprotect-fhs.nix { inherit pkgs; }) "globalprotect-agent-fhs";

  portal = "secureaccess.luc.edu";
  username = "jgutierrez11@luc.edu";

  # `connect` needs interactive credential/SSO input, so this has to be run
  # directly in a real terminal -- never from a non-interactive context, it
  # just hangs waiting for a TTY.
  vpnConnect = pkgs.writeShellApplication {
    name = "coel-vpn-connect";
    runtimeInputs = [ gpFHS ];
    text = ''
      exec globalprotect-agent-fhs -c "cd /opt/paloaltonetworks/globalprotect && ./globalprotect connect --portal ${portal} --username ${username}"
    '';
  };

  # Uses the system daemon's FHS wrapper (globalprotect-fhs, from
  # modules/globalprotect.nix), not the agent's -- both talk to the same
  # running PanGPA, but disconnect doesn't need the agent-specific one.
  # Already guaranteed on PATH via environment.systemPackages there.
  vpnDisconnect = pkgs.writeShellApplication {
    name = "coel-vpn-disconnect";
    text = ''
      exec globalprotect-fhs -c 'cd /opt/paloaltonetworks/globalprotect && ./globalprotect disconnect'
    '';
  };
in
{
  # Exposes `globalprotect-agent-fhs` on PATH so the vendor `globalprotect`
  # CLI (connect/disconnect/show --status) can be run by hand -- it was
  # previously only reachable via its full store path inside the systemd
  # service below.
  home.packages = [ gpFHS vpnConnect vpnDisconnect ];

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

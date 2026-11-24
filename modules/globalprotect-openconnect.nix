# openconnect backend for the LUC GlobalProtect VPN. Replaced the vendored
# PanGPS/PanGPA client (its own module, FHS sandbox and binaries all
# removed once this was proven working against the real gateway -- see
# [[project_globalprotect_luc]]).
#
# Split into two privilege levels, the same shape the old vendor client
# used (root daemon / user agent), for the same reason: openconnect itself
# needs root to create the tun device, but authenticating to the portal
# doesn't:
#
#   1. Unprivileged: `openconnect --authenticate` does the portal/gateway
#      login (home/globalprotect/openconnect-authenticate.exp, driven by
#      coel-vpn-connect) and writes the resulting session cookie to the
#      invoking user's own XDG runtime dir -- never to argv, never logged.
#
#   2. Root, on demand: `openconnect-luc@<uid>.service` reads that cookie and
#      makes the actual tunnel. Started/stopped via `systemctl` by the user
#      wrapper, authorized by the narrow polkit rule below instead of a
#      persistent always-on daemon -- unlike the old vendor daemon, there's
#      nothing for it to do while disconnected.
#
# The HIP report sent during connection is genuine (see
# globalprotect/openconnect-hipreport.sh for why) -- queried live from this
# host, not vendored OPSWAT-based detection running inside a sandbox.
{ pkgs, ... }:

let
  hipWrapper = pkgs.writeShellApplication {
    name = "coel-openconnect-hipreport";
    runtimeInputs = [
      pkgs.openconnect
      pkgs.iproute2
      pkgs.nftables
      pkgs.iptables
      pkgs.systemd
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.coreutils
    ];
    text = builtins.readFile ./globalprotect/openconnect-hipreport.sh;
  };

  lucRun = pkgs.writeShellApplication {
    name = "coel-openconnect-luc-run";
    runtimeInputs = [
      pkgs.openconnect
      pkgs.coreutils
      pkgs.iproute2
    ];
    text =
      "export HIP_WRAPPER=${hipWrapper}/bin/coel-openconnect-hipreport\n"
      + builtins.readFile ./globalprotect/openconnect-luc-run.sh;
  };
in
{
  environment.systemPackages = [
    pkgs.openconnect
    hipWrapper
    lucRun
  ];

  security.polkit.extraConfig = builtins.readFile ./globalprotect/openconnect-luc-polkit.js;

  # Instantiated per-uid so the unit name itself carries no secret, only a
  # number already visible in `id`/`ls -l /home` -- the polkit rule above
  # checks the literal instance "1000" (this host's only real user), not a
  # wildcard, so a different uid can't self-authorize by picking its own
  # instance name.
  systemd.services."openconnect-luc@" = {
    description = "openconnect tunnel to LUC GlobalProtect (uid %i)";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lucRun}/bin/coel-openconnect-luc-run %i";
      # No Restart=: a cookie is single-use and the session file is deleted
      # once read, so an automatic restart after this exits would just fail
      # outright instead of reconnecting -- a fresh coel-vpn-connect run
      # (fresh cookie) is what actually recovers a dropped tunnel.
      Restart = "no";
    };
  };
}

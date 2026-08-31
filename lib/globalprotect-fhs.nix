# Shared FHS-environment builder for GlobalProtect (daemon + agent).
# Both modules/globalprotect.nix (system daemon) and home/globalprotect.nix
# (user agent) call this with a different `name` so the derivation/binary
# names don't collide, but the runtime deps and bind-mount are identical.
{ pkgs }:

name:

pkgs.buildFHSEnv {
  inherit name;
  targetPkgs = pkgs: with pkgs; [
    stdenv.cc.cc.lib
    iproute2   # PanGPS shells out to `ip` for client-ip/route lookups during HIP checks
    iputils    # ping, used internally by some GP network checks
    procps     # ps, used by vendor scripts (gpshow.sh / gp_support.sh)
    gawk
    gnugrep
    gnused
    coreutils

    # PanGpHip's OPSWAT-based HIP "firewall" check runs *inside* this
    # sandbox, so it can only see binaries present in this list -- it has
    # no visibility into the real host's actual firewall regardless of
    # what's genuinely running there. Confirmed on a clean Ubuntu VM test
    # that OPSWAT names "IPTables" and "nftables" as separate detected
    # products by finding these tools directly, not by querying a package
    # database, so just making the binaries reachable here should be
    # enough for it to find them the same way. (ufw isn't packaged in
    # nixpkgs, so not included -- iptables + nftables covers 2 of the 3
    # products Ubuntu's report showed.) See globalprotect-hip-investigation.md.
    iptables
    nftables
  ];
  extraBwrapArgs = [
    "--bind" "/var/lib/globalprotect" "/opt/paloaltonetworks/globalprotect"
  ];
  runScript = "/bin/sh";
}

# Shared FHS-environment builder for GlobalProtect (daemon + agent).
# Both modules/globalprotect.nix (system daemon) and home/globalprotect.nix
# (user agent) call this with a different `name` so the derivation/binary
# names don't collide, but the runtime deps and bind-mount are identical.
{ pkgs }:

name:

pkgs.buildFHSEnv {
  inherit name;
  targetPkgs =
    pkgs: with pkgs; [
      stdenv.cc.cc.lib
      iproute2 # PanGPS shells out to `ip` for client-ip/route lookups during HIP checks
      iputils # ping, used internally by some GP network checks
      procps # ps, used by vendor scripts (gpshow.sh / gp_support.sh)
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
    "--bind"
    "/var/lib/globalprotect"
    "/opt/paloaltonetworks/globalprotect"

    # bwrap unconditionally sets no_new_privs before exec'ing the sandboxed
    # program. Combined with an empty inheritable capability set (the
    # ordinary default) and no file capabilities on the vendor binaries,
    # that zeroes out the *effective*/*permitted* capability sets at exec
    # time even for the root-run daemon (confirmed live: CapBnd was a full
    # set, CapEff/CapPrm were both 0) -- root in name only, with none of
    # root's actual privileges surviving into the sandbox. PanGPS needs
    # CAP_NET_ADMIN to create/configure its own tunnel interface; without
    # it, login/auth to the gateway succeeds (plain network I/O, no
    # privilege needed) but interface setup fails right after with
    # "ioctl() failed on SIOCGIFFLAGS ... No such device", which is
    # PanGPS's own log for "I have no privilege to bring up gpd0". Added
    # CAP_NET_RAW too since VPN clients commonly need it for the same class
    # of low-level network operations (this FHS env already ships `ping`
    # for GP's own internal network checks, which needs it too). Only has
    # any effect for a bwrap invocation running as a privileged (root)
    # caller -- see `bwrap --help` -- so this is a no-op for the per-user
    # agent's own (unprivileged) sandbox.
    "--cap-add"
    "CAP_NET_ADMIN"
    "--cap-add"
    "CAP_NET_RAW"
  ];
  extraInstallCommands = "mkdir -p $out/opt/paloaltonetworks/globalprotect";
  runScript = "/bin/sh";
}

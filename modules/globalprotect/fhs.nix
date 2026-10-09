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
      # sandbox, so it can only see binaries present in this list, not the
      # real host's actual firewall. OPSWAT detects "IPTables"/"nftables" by
      # finding these tools directly, not by querying a package database
      # (ufw isn't packaged in nixpkgs, so not included). See
      # modules/globalprotect/globalprotect-hip-investigation.md.
      iptables
      nftables
    ];
  extraBwrapArgs = [
    "--bind"
    "/var/lib/globalprotect"
    "/opt/paloaltonetworks/globalprotect"

    # bwrap unconditionally sets no_new_privs before exec'ing the sandboxed
    # program, which zeroes out the effective/permitted capability sets at
    # exec time even for the root-run daemon -- root in name only, with none
    # of root's actual privileges surviving into the sandbox. PanGPS needs
    # CAP_NET_ADMIN to bring up its own tunnel interface; without it, login
    # succeeds but interface setup fails with "ioctl() failed on
    # SIOCGIFFLAGS ... No such device". CAP_NET_RAW added too for the same
    # class of low-level network operations (`ping`, used by GP's own
    # internal checks, needs it). Only has any effect for a privileged
    # (root) bwrap caller, so this is a no-op for the per-user agent's own
    # unprivileged sandbox.
    "--cap-add"
    "CAP_NET_ADMIN"
    "--cap-add"
    "CAP_NET_RAW"
  ];
  extraInstallCommands = "mkdir -p $out/opt/paloaltonetworks/globalprotect";
  runScript = "/bin/sh";
}

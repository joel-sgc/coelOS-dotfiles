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
  ];
  extraBwrapArgs = [
    "--bind" "/var/lib/globalprotect" "/opt/paloaltonetworks/globalprotect"
  ];
  runScript = "/bin/sh";
}

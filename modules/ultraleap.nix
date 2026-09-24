# Ultraleap Gemini hand tracking (the driver/daemon for a Leap Motion
# camera). Ultraleap's own Linux distribution (repo.ultraleap.com, the
# tracking-software-download page) has gone dark; this instead builds the
# service from the last hash-pinned .deb this flake still references, and
# provides leapc-cffi/leapc-python-api as proper Nix-built Python packages
# (needed on NixOS since a plain pip/uv build of the CFFI extension won't
# find libLeapC.so at runtime without FHS-style paths).
#
# The fixed-output .debs (repo.ultraleap.com is unreachable) are supplied by
# adding them to the local Nix store out-of-band, matching this flake's
# pinned hashes exactly:
#   nix-store --add-fixed sha256 ultraleap-hand-tracking-service_5.17.1.0-a9f25232-1.0_amd64.deb
#   nix-store --add-fixed sha256 openxr-layer-ultraleap_1.6.5-2B2486adf9.CI1130164_amd64.deb
#
# The vendor's own shipped udev rules (lib/udev/rules.d/99-{LMC,LMC2,SIR170}.rules,
# one per supported device ID) are all malformed the same way: a stray blank
# line splits each into a no-op match rule and a separate GROUP assignment
# with no match criteria of its own. NixOS's udev-rules build runs `udevadm
# verify` and hard-fails on this (a real system's udevd would just warn and
# ignore the broken line), so the package derivation is overridden below to
# rejoin each file's two non-blank lines into one valid rule. extraRules adds
# a redundant, group-independent MODE="0666" fallback for the one device we
# actually have.
#
# leapd's tracking-model search path (`/usr/share/ultraleap`) is a hardcoded
# FHS absolute path baked into the binary -- there's no env var or config
# override for it (checked /etc/ultraleap/hand_tracker_config.json, nothing
# there either). NixOS doesn't populate /usr, so leapd finds 0 LDATs and
# refuses to start a tracker. tmpfiles.rules below symlinks that path at the
# package's own $out/share/ultraleap, the same trick already used for
# /etc/ultraleap below.
#
# leapc-cffi's own (unpatched, upstream) setup.py -- what a plain `uv sync
# --extra leap` actually builds, as opposed to this flake's own patched Nix
# package.nix for it -- falls back to the same kind of hardcoded FHS defaults
# when LEAPC_HEADER_OVERRIDE/LEAPC_LIB_OVERRIDE aren't set:
# /usr/include/LeapC.h and /usr/lib/ultraleap-hand-tracking-service/libLeapC.so.
# Symlinking those too means `uv sync` needs no special env vars.
{ inputs, pkgs, ... }:

{
  imports = [ inputs.ultraleap-nix.nixosModules.default ];
  nixpkgs.overlays = [
    inputs.ultraleap-nix.overlays.default
    (final: prev: {
      ultraleap-hand-tracking-service = prev.ultraleap-hand-tracking-service.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          for f in "$out"/lib/udev/rules.d/99-LMC.rules \
                   "$out"/lib/udev/rules.d/99-LMC2.rules \
                   "$out"/lib/udev/rules.d/99-SIR170.rules; do
            grep -v '^[[:space:]]*$' "$f" | paste -sd, - > "$f.fixed"
            mv "$f.fixed" "$f"
          done
        '';
      });
    })
  ];

  services.ultraleap.enable = true;

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTRS{idVendor}=="f182", ATTRS{idProduct}=="0003", MODE="0666"
  '';

  systemd.tmpfiles.rules = [
    "d /usr/share 0755 root root -"
    "d /usr/include 0755 root root -"
    "d /usr/lib 0755 root root -"
    "L+ /usr/share/ultraleap - - - - ${pkgs.ultraleap-hand-tracking-service}/share/ultraleap"
    "L+ /usr/include/LeapC.h - - - - ${pkgs.ultraleap-hand-tracking-service.dev}/include/LeapC.h"
    "L+ /usr/lib/ultraleap-hand-tracking-service - - - - ${pkgs.ultraleap-hand-tracking-service}/lib"
  ];
}

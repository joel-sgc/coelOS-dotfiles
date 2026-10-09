# Ultraleap Gemini hand tracking (driver/daemon for a Leap Motion camera).
# Ultraleap's own Linux distribution has gone dark; this builds the service
# from the last hash-pinned .deb this flake still references, and provides
# leapc-cffi/leapc-python-api as proper Nix-built Python packages (needed
# since a plain pip/uv build of the CFFI extension won't find libLeapC.so
# at runtime without FHS-style paths).
#
# The fixed-output .debs are supplied by adding them to the local Nix store
# out-of-band, matching this flake's pinned hashes exactly:
#   nix-store --add-fixed sha256 ultraleap-hand-tracking-service_5.17.1.0-a9f25232-1.0_amd64.deb
#   nix-store --add-fixed sha256 openxr-layer-ultraleap_1.6.5-2B2486adf9.CI1130164_amd64.deb
# --add-fixed paths are NOT GC roots: `nix-collect-garbage` deletes them and
# the build then tries the dead repo.ultraleap.com URL. Root them:
#   nix-store --add-root ~/.local/state/nix-roots/ultraleap-service-deb --indirect -r <store path>
# Everything here is built from nixpkgs-pinned (see flake.nix) so these are
# only needed again if that pin is bumped.
#
# The vendor's shipped udev rules (lib/udev/rules.d/99-{LMC,LMC2,SIR170}.rules)
# are malformed: a stray blank line splits each into a no-op match rule and a
# separate GROUP assignment with no match criteria. NixOS's udev-rules build
# hard-fails `udevadm verify` on this, so the derivation below rejoins each
# file's two non-blank lines into one valid rule. extraRules adds a
# redundant MODE="0666" fallback for the one device we actually have.
#
# leapd's tracking-model search path (`/usr/share/ultraleap`) is a hardcoded
# FHS path baked into the binary with no override. NixOS doesn't populate
# /usr, so leapd finds 0 LDATs and refuses to start a tracker.
# tmpfiles.rules below symlinks that path at the package's own
# $out/share/ultraleap, same trick used for /etc/ultraleap below.
#
# leapc-cffi's own unpatched setup.py (what plain `uv sync --extra leap`
# builds) falls back to the same kind of hardcoded FHS defaults when
# LEAPC_HEADER_OVERRIDE/LEAPC_LIB_OVERRIDE aren't set. Symlinking those too
# means `uv sync` needs no special env vars.
{ inputs, pkgs, pkgs-pinned, ... }:

let
  pinnedUltraleap = pkgs-pinned.extend (
    pkgs.lib.composeManyExtensions [
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
    ]
  );
in
{
  imports = [ inputs.ultraleap-nix.nixosModules.default ];
  # The service (and OpenXR layer) come from the frozen nixpkgs-pinned set so
  # a `nix flake update` of the main nixpkgs doesn't re-unpack and re-patchelf
  # the 666MB .deb. The upstream overlay still goes on the main set for the
  # Python bindings, which pick up the pinned service via `final`.
  nixpkgs.overlays = [
    inputs.ultraleap-nix.overlays.default
    (final: prev: {
      inherit (pinnedUltraleap) ultraleap-hand-tracking-service openxr-ultraleap-layer;
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

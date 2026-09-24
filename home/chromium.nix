{ pkgs, ... }:

{
  programs.chromium = {
    enable = true;
    package = pkgs.chromium;

    # No commandLineArgs for Wayland: nixpkgs' chromium wrapper already
    # switches to the native Wayland backend when NIXOS_OZONE_WL is set,
    # which home.nix sets globally.

    # Same pair as home/zen-browser.nix. Find IDs in the Chrome Web Store URL.
    # These are dropped in ~/.config/chromium/External Extensions/ and get
    # offered for install on the next launch (Chromium asks you to enable
    # them once from the toolbar menu).
    extensions = [
      # uBlock Origin *Lite*, not classic uBlock Origin: Chromium dropped
      # Manifest V2 entirely (we're on 150), and classic uBO is MV2 only,
      # so it would silently fail to load.
      { id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; } # uBlock Origin Lite
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
    ];
  };
}

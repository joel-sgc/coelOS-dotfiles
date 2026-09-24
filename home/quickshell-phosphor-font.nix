# Vendors the Phosphor icon font (not packaged in nixpkgs under any name as
# of writing -- checked "phosphor-icons"/"phosphor-icon-font"/"phosphor").
# Only the Regular weight, since that's the only one the panel currently
# needs; add a second fetchurl here if a later phase wants Fill/Bold too.
#
# Source: phosphor-icons/web, which vendors the prebuilt font (the same
# package the design mockup's own CDN link -- unpkg @phosphor-icons/web --
# serves). Pinned to tag v2.1.2 rather than master so the hash stays valid.
{ pkgs }:

pkgs.runCommand "phosphor-icons-font" { } ''
  install -Dm444 ${
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/phosphor-icons/web/v2.1.2/src/regular/Phosphor.ttf";
      sha256 = "041s2w6j4qznx5kl8km5pnn0nkx7ja9qgvgw7sk9ks3y5c11xf86";
    }
  } $out/share/fonts/truetype/Phosphor.ttf
''

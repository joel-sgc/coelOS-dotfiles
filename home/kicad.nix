{ pkgs, ... }:

{
  # EDA suite (schematic capture + PCB layout). User-facing desktop app, same
  # category as gimp/vscode, but broken out into its own file rather than
  # home.nix's plain package list since it's plausible this grows real
  # config later (library paths, theming) -- easier to find and extend here.
  #
  # No home-manager-level config yet; upstream's own .desktop entries
  # (org.kicad.*) already put "KiCad" in Name, so unlike gimp.desktop this
  # needs no home/desktop-entries.nix override.
  home.packages = [
    pkgs.kicad
  ];
}

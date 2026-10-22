{ pkgs, lib, ... }:

let
  setWallpaper = pkgs.writeShellApplication {
    name = "coel-set-wallpaper";
    runtimeInputs = [ pkgs.awww ];
    text = ''
      if [ $# -lt 1 ]; then
        echo "Usage: coel-set-wallpaper <path-to-image>" >&2
        exit 1
      fi

      awww img "$1"
    '';
  };

  # Symlinked from the vendored set in assets/wallpapers rather than
  # referenced by its ~/.nixos checkout path directly, so the picker below
  # still works even if the repo ever moves.
  wallpaperDir = "Pictures/wallpapers";

  randomWallpaper = pkgs.writeShellApplication {
    name = "coel-random-wallpaper";
    runtimeInputs = [
      pkgs.findutils
      pkgs.coreutils
      setWallpaper
    ];
    text =
      "WALLPAPER_DIR_REL=${lib.escapeShellArg wallpaperDir}\n"
      + builtins.readFile ./wallpaper/random-wallpaper.sh;
  };
in
{
  # Wallpaper daemon. `swww` was renamed upstream to `awww`.
  #
  # `coel-random-wallpaper` picks a random image from the vendored set
  # (assets/wallpapers) and applies it via awww on Hyprland or
  # -- wired to run once per session from home/hyprland.nix's exec-once.
  # Theming stays static (home/theme.nix), not derived from the wallpaper.
  services.awww.enable = true;

  home.file.${wallpaperDir}.source = ../assets/wallpapers;

  home.packages = [
    setWallpaper
    randomWallpaper
  ];
}

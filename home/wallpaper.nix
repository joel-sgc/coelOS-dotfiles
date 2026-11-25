{ pkgs, lib, ... }:

let
  setWallpaper = pkgs.writeShellApplication {
    name = "coel-set-wallpaper";
    runtimeInputs = [ pkgs.coreutils ];
    # Quickshell draws the wallpaper (home/quickshell/Wallpaper.qml). If it
    # isn't up yet, it reads the state file when it starts.
    text = ''
      if [ $# -lt 1 ] || [ ! -f "$1" ]; then
        echo "Usage: coel-set-wallpaper <path-to-image>" >&2
        exit 1
      fi

      state="$XDG_RUNTIME_DIR/coel-wallpaper"
      realpath -- "$1" > "$state.tmp"
      mv "$state.tmp" "$state"
      quickshell ipc -p "$HOME/.nixos/home/quickshell" call wallpaper reload >/dev/null 2>&1 || true
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
  # `coel-random-wallpaper` picks a random image from the vendored set
  # (assets/wallpapers); hyprland.lua runs it once per session. Theming stays
  # static (home/theme.nix), not derived from the wallpaper.
  home.file.${wallpaperDir}.source = ../assets/wallpapers;

  home.packages = [
    setWallpaper
    randomWallpaper
    pkgs.qt6.qtimageformats # webp decoding for Quickshell
  ];
}

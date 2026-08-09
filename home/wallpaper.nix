{ config, pkgs, ... }:

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
in
{
  # Wallpaper daemon. `swww` was renamed upstream to `awww`; this is the
  # same tool your old Arch config used (as `swww`/`swww-daemon`).
  #
  # Daemon only for now — no wallpaper image or the old 30min cycling script
  # ported yet, since that needs the actual image assets pulled over from
  # the old dotfiles repo. `coel-set-wallpaper <path>` is the mechanism once
  # you have one. Theming is static (Everforest, see home/theme.nix) and no
  # longer derived from the wallpaper.
  services.awww.enable = true;

  home.packages = [ setWallpaper ];
}

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

  # Symlinked from the vendored set in assets/wallpapers (see the README
  # there) rather than referenced by its ~/.nixos checkout path directly --
  # this way the picker below still works even if the repo ever moves, and
  # it's the same declarative "copy into $HOME" pattern already used for
  # micro's LSP plugin (home/micro.nix's `xdg.configFile."micro/plug/lsp"`).
  wallpaperDir = "Pictures/wallpapers";

  randomWallpaper = pkgs.writeShellApplication {
    name = "coel-random-wallpaper";
    runtimeInputs = [ pkgs.findutils pkgs.coreutils setWallpaper pkgs.kdePackages.plasma-workspace ];
    text = ''
      wallpaper_dir="$HOME/${wallpaperDir}"

      mapfile -t candidates < <(
        find -L "$wallpaper_dir" -maxdepth 1 -type f \
          \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \)
      )
      if [ "''${#candidates[@]}" -eq 0 ]; then
        echo "coel-random-wallpaper: no wallpapers found in $wallpaper_dir" >&2
        exit 1
      fi
      pick="''${candidates[RANDOM % ''${#candidates[@]}]}"

      case "''${XDG_CURRENT_DESKTOP:-}" in
        *Hyprland*)
          # Runs from Hyprland's exec-once (home/hyprland.nix), which can
          # race the awww daemon's own systemd-user startup -- retry for a
          # few seconds rather than silently doing nothing on a fast login.
          for _ in $(seq 1 10); do
            if coel-set-wallpaper "$pick"; then
              exit 0
            fi
            sleep 0.5
          done
          echo "coel-random-wallpaper: awww daemon never became ready" >&2
          exit 1
          ;;
        *KDE*)
          plasma-apply-wallpaperimage "$pick"
          ;;
        *)
          echo "coel-random-wallpaper: unrecognized XDG_CURRENT_DESKTOP [''${XDG_CURRENT_DESKTOP:-}], doing nothing" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  # Wallpaper daemon. `swww` was renamed upstream to `awww`; this is the
  # same tool your old Arch config used (as `swww`/`swww-daemon`).
  #
  # `coel-random-wallpaper` picks a random image from the vendored set
  # (assets/wallpapers, see its README) and applies it via awww on
  # Hyprland or plasma-apply-wallpaperimage on Plasma -- wired to run once
  # per session on both (home/hyprland.nix's exec-once here; Plasma's side
  # is home/kde-wallpaper.nix, an XDG autostart entry, since that's the
  # actual "once per login" hook Plasma provides). Theming itself stays
  # static (home/theme.nix) either way, not derived from the wallpaper.
  services.awww.enable = true;

  home.file.${wallpaperDir}.source = ../assets/wallpapers;

  home.packages = [ setWallpaper randomWallpaper ];
}

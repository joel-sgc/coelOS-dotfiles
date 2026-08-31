wallpaper_dir="$HOME/$WALLPAPER_DIR_REL"

mapfile -t candidates < <(
  find -L "$wallpaper_dir" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \)
)
if [ "${#candidates[@]}" -eq 0 ]; then
  echo "coel-random-wallpaper: no wallpapers found in $wallpaper_dir" >&2
  exit 1
fi
pick="${candidates[RANDOM % ${#candidates[@]}]}"

case "${XDG_CURRENT_DESKTOP:-}" in
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
    echo "coel-random-wallpaper: unrecognized XDG_CURRENT_DESKTOP [${XDG_CURRENT_DESKTOP:-}], doing nothing" >&2
    exit 1
    ;;
esac

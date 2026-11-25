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

coel-set-wallpaper "$pick"

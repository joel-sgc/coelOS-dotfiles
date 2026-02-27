#!/usr/bin/env bash

WALLDIR="$HOME/Pictures/Wallpapers"

# Get list of images (follow symlinks)
mapfile -t IMAGES < <(find -L "$WALLDIR" -type f)

# Exit if no images
[ ${#IMAGES[@]} -eq 0 ] && exit 1

# Shuffle images
mapfile -t SHUFFLED < <(printf "%s\n" "${IMAGES[@]}" | shuf)

i=0

# Extract monitor names cleanly
while read -r OUTPUT; do
  IMG="${SHUFFLED[$i]}"

  # If we run out of images, reshuffle and start again
  if [ -z "$IMG" ]; then
    mapfile -t SHUFFLED < <(printf "%s\n" "${IMAGES[@]}" | shuf)
    i=0
    IMG="${SHUFFLED[$i]}"
  fi

  swww img -o "$OUTPUT" "$IMG" \
    --transition-type any \
    --transition-duration 1.2 \
    --transition-fps 60

  ((i++))
done < <(swww query | sed -E 's/^: ([^:]+):.*/\1/')

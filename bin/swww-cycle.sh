#!/usr/bin/env bash

WALLDIR="$HOME/Pictures/Wallpapers"

IMG=$(find "$WALLDIR" | shuf -n 1)

swww img "$IMG" \
  --transition-type any \
  --transition-duration 1.2 \
  --transition-fps 60

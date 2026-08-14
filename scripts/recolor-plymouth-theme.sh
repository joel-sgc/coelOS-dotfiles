#!/usr/bin/env bash
#
# Recolors the CoelOS Plymouth boot-splash assets (lock/entry/bullet/
# progress bar+box, and the ascii-art logo) to new target colors, while
# preserving each file's exact alpha channel (shape/edge antialiasing).
# These are flat single-color glyphs, not gradient-shaded art -- all their
# "detail" lives in alpha, not RGB variation (confirmed by inspecting
# their histograms), so a plain flat recolor-preserving-alpha reproduces
# the original look exactly, just in a new color.
#
# Usage: recolor-plymouth-theme.sh [--logo COLOR] [--accent COLOR] [--track COLOR]
#
# Requires ImageMagick (`magick`), generate-logo.sh in this same directory,
# and ascii-name.txt one level up (coelos-dotfiles/ascii-name.txt).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOGO_COLOR="#61afef"    # ascii-name.txt logo fill (currently theme.blue)
ACCENT_COLOR="#e5c07b"  # bullet / entry / lock / progress_bar fill (currently theme.yellow)
TRACK_COLOR="#404754"   # progress_box fill (currently theme.surface) -- deliberately
                         # different from ACCENT_COLOR, otherwise the growing
                         # progress_bar blends into its own track and the fill
                         # animation stops being visible

# Every directory that should end up with a copy of the recolored assets.
# coelos-theme/ (repo root) is what configuration.nix's boot.plymouth
# actually builds from; configs/plymouth/ (coelos-dotfiles root) is kept
# in sync as reference/backup.
TARGET_DIRS=(
  "$SCRIPT_DIR/../../coelos-theme"
  "$SCRIPT_DIR/../configs/plymouth"
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [--logo COLOR] [--accent COLOR] [--track COLOR]

Recolors the Plymouth theme assets in:
$(printf '  %s\n' "${TARGET_DIRS[@]}")

  --logo COLOR    ascii-name.txt logo fill (default: $LOGO_COLOR)
  --accent COLOR  bullet/entry/lock/progress_bar fill (default: $ACCENT_COLOR)
  --track COLOR   progress_box fill -- keep distinct from --accent, or the
                  progress bar will blend into its own track (default: $TRACK_COLOR)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --logo) LOGO_COLOR="$2"; shift 2 ;;
    --accent) ACCENT_COLOR="$2"; shift 2 ;;
    --track) TRACK_COLOR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

command -v magick >/dev/null || { echo "ImageMagick's 'magick' not found in PATH" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Recolors a single flat-color PNG, keeping its alpha channel byte-for-byte
# identical to the source.
recolor_flat() {
  local src="$1" color="$2" out="$3"
  local dim
  dim="$(identify -format '%wx%h' "$src")"
  magick "$src" -alpha extract "$WORK/alpha.png"
  magick -size "$dim" xc:"$color" "$WORK/solid.png"
  magick "$WORK/solid.png" "$WORK/alpha.png" -alpha off -compose CopyOpacity -composite "$out"
}

# Alpha shapes are read from coelos-theme/ regardless of which target
# directory is currently being written -- safe even when coelos-theme/ is
# itself one of the targets, since we only ever reuse its alpha channel,
# which this script never modifies.
SRC_DIR="$SCRIPT_DIR/../../coelos-theme"

for target in "${TARGET_DIRS[@]}"; do
  mkdir -p "$target"

  for f in bullet entry lock progress_bar; do
    recolor_flat "$SRC_DIR/$f.png" "$ACCENT_COLOR" "$target/$f.png"
  done
  recolor_flat "$SRC_DIR/progress_box.png" "$TRACK_COLOR" "$target/progress_box.png"

  bash "$SCRIPT_DIR/generate-logo.sh" "$SCRIPT_DIR/../ascii-name.txt" "$target/logo.png" "$LOGO_COLOR"
done

echo "Recolored Plymouth theme assets:"
echo "  logo:   $LOGO_COLOR"
echo "  accent: $ACCENT_COLOR (bullet/entry/lock/progress_bar)"
echo "  track:  $TRACK_COLOR (progress_box)"
echo
echo "Rebuild to apply: nix build .#nixosConfigurations.coelos.config.system.build.toplevel"

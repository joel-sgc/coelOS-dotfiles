#!/usr/bin/bash

# Usage:
# ./generate-logo.sh ascii-name.txt logo.png "#ff99da"

INPUT="$1"
OUTPUT="$2"
COLOR="${3:-black}"

CELL_W=5
CELL_H=10

if [[ -z "$INPUT" || -z "$OUTPUT" ]]; then
  echo "Usage: $0 ascii-name.txt logo.png [color]"
  exit 1
fi

# Determine dimensions in characters
WIDTH_CHARS=$(awk '{ if (length > max) max = length } END { print max }' "$INPUT")
HEIGHT_CHARS=$(wc -l < "$INPUT")

# Convert to pixels
WIDTH_PX=$((WIDTH_CHARS * CELL_W))
HEIGHT_PX=$((HEIGHT_CHARS * CELL_H))

# Initialize ImageMagick command
CMD=(
  magick
  -size "${WIDTH_PX}x${HEIGHT_PX}"
  xc:none
  -fill "$COLOR"
)

y=0
while IFS= read -r line; do
  x=0
  for (( i=0; i<${#line}; i++ )); do
    char="${line:i:1}"
    if [[ "$char" != " " ]]; then
      x1=$((x * CELL_W))
      y1=$((y * CELL_H))
      x2=$((x1 + CELL_W - 1))
      y2=$((y1 + CELL_H - 1))
      CMD+=(-draw "rectangle $x1,$y1 $x2,$y2")
    fi
    ((x++))
  done
  ((y++))
done < "$INPUT"

CMD+=("$OUTPUT")

# Execute
"${CMD[@]}"
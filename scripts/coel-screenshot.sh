OUTPUT_DIR="$HOME/Pictures/Screenshots"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  notify-send "Screenshot directory does not exist: $OUTPUT_DIR" -u critical -t 3000
  exit 1
fi

pkill slurp && exit 0

MODE="${1:-smart}"
PROCESSING="${2:-slurp}"

# Tells Panel.qml's dropdowns (Popup.qml) to defer their own focus-grab
# auto-close for the duration of this run -- wayfreeze/slurp below steal
# keyboard/pointer focus to do their job, which would otherwise close
# whatever popup is open right as it's being screenshotted. The trap
# guarantees the "stop" call still happens on any exit path (empty
# selection, an error, Print pressed again to cancel), not just the
# normal end of the script -- Panel.qml also has its own timeout as a
# second safety net in case this process gets killed outright (SIGKILL,
# which skips EXIT traps).
trap 'quickshell ipc -p ~/.nixos/home/quickshell call screenshot stop >/dev/null 2>&1 || true' EXIT
quickshell ipc -p ~/.nixos/home/quickshell call screenshot start >/dev/null 2>&1 || true

get_rectangles() {
  local active_workspace
  active_workspace=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .activeWorkspace.id')
  hyprctl monitors -j | jq -r --arg ws "$active_workspace" '.[] | select(.activeWorkspace.id == ($ws | tonumber)) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"'
  hyprctl clients -j | jq -r --arg ws "$active_workspace" '.[] | select(.workspace.id == ($ws | tonumber)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

# `kill` only sends SIGTERM -- it doesn't block until wayfreeze has
# actually exited, let alone until the compositor has torn down its
# frozen-frame overlay and rendered a clean frame afterward. `wait`ing
# for the process to really be gone, then giving the compositor one more
# beat to redraw, closes that small window before grim's live capture.
kill_freeze() {
  kill "$1" 2>/dev/null
  # `wait` on a process killed by a signal reports that as a non-zero
  # exit (128+15 for SIGTERM) -- under this script's `set -e`, letting
  # that propagate kills the whole script right here, silently, before
  # grim/satty ever runs. That's not a failure worth stopping for: we
  # killed it on purpose, we just want to know it's actually gone.
  wait "$1" 2>/dev/null || true
  sleep 0.05
}

sleep 0.05

case "$MODE" in
  region)
    wayfreeze & PID=$!
    sleep .1
    SELECTION=$(slurp 2>/dev/null)
    kill_freeze "$PID"
    ;;
  windows)
    wayfreeze & PID=$!
    sleep .1
    SELECTION=$(get_rectangles | slurp -r 2>/dev/null)
    kill_freeze "$PID"
    ;;
  fullscreen)
    SELECTION=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"')
    ;;
  smart | *)
    RECTS=$(get_rectangles)
    wayfreeze & PID=$!
    sleep .1
    SELECTION=$(echo "$RECTS" | slurp 2>/dev/null)
    kill_freeze "$PID"

    if [[ "$SELECTION" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
      if (( BASH_REMATCH[3] * BASH_REMATCH[4] < 20 )); then
        click_x="${BASH_REMATCH[1]}"
        click_y="${BASH_REMATCH[2]}"

        while IFS= read -r rect; do
          if [[ "$rect" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+) ]]; then
            rect_x="${BASH_REMATCH[1]}"
            rect_y="${BASH_REMATCH[2]}"
            rect_width="${BASH_REMATCH[3]}"
            rect_height="${BASH_REMATCH[4]}"

            if (( click_x >= rect_x && click_x < rect_x+rect_width && click_y >= rect_y && click_y < rect_y+rect_height )); then
              SELECTION="$rect_x,$rect_y ${rect_width}x${rect_height}"
              break
            fi
          fi
        done <<< "$RECTS"
      fi
    fi
    ;;
esac

[ -z "$SELECTION" ] && exit 0

if [[ $PROCESSING == "slurp" ]]; then
  grim -g "$SELECTION" - |
    satty --filename - \
      --output-filename "$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png" \
      --early-exit \
      --actions-on-enter save-to-clipboard \
      --save-after-copy \
      --copy-command 'wl-copy'
else
  grim -g "$SELECTION" - | wl-copy
fi

mic_active=false
if pw-dump 2>/dev/null | jq -e '
  any(.[]?; (.info.props["media.class"]? // "") == "Stream/Input/Audio" and .info.state == "running")
' >/dev/null 2>&1; then
  mic_active=true
fi

camera_active=false
shopt -s nullglob
for dev in /dev/video*; do
  if fuser "$dev" >/dev/null 2>&1; then
    camera_active=true
    break
  fi
done
shopt -u nullglob

text=""
tooltip_lines=()

if [ "$mic_active" = true ]; then
  text+=" "
  tooltip_lines+=("Microphone in use")
fi

if [ "$camera_active" = true ]; then
  text+=""
  tooltip_lines+=("Camera in use")
fi

tooltip=$(printf '%s\n' "${tooltip_lines[@]-}")
jq -nc --arg text "$text" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'

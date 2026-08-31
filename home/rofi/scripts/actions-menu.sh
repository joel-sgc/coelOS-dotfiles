#!/usr/bin/env bash
choice=$(printf \
" 󰄀  Screenshot\n\
 Screen Record\n\
 Color\n" | rofi -dmenu -i -p "Actions" -lines 10 -no-fixed-num-lines)

exit_code=$?

case "$choice" in
	*Screenshot*) exec coel-screenshot ;;
	*Record*) exec coel-screenrecord ;;
	*Color*) exec bash -c "sleep 0.15 && hyprpicker -a" ;;
esac

if [ "$exit_code" -ne 0 ]; then
    exec coel-main-menu
fi


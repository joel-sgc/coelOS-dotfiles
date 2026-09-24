#!/usr/bin/env bash
# @icon:<name>@ placeholders are filled with Nerd Font glyphs at build time
# (see power-menu.sh / home/icons.nix). Don't paste the glyphs in here.
choice=$(printf \
"@icon:screenshot@  Screenshot\n\
@icon:screen-record@  Screen Record\n\
@icon:color@  Color\n" | rofi -dmenu -i -p "Actions" -lines 10 -no-fixed-num-lines)

exit_code=$?

case "$choice" in
	*Screenshot*) exec coel-screenshot ;;
	*Record*) exec coel-screenrecord ;;
	*Color*) exec bash -c "sleep 0.15 && hyprpicker -a" ;;
esac

if [ "$exit_code" -ne 0 ]; then
    exec coel-main-menu
fi

#!/usr/bin/env bash
# @icon:<name>@ placeholders are filled with Nerd Font glyphs at build time
# (withIcons in home/rofi.nix, icons defined in home/icons.nix). Don't paste
# the glyphs in here: they're invisible to AI assistants and get silently
# dropped whenever one rewrites the file.
choice=$(printf \
"@icon:lock@  Lock\n\
@icon:logout@  Logout\n\
@icon:suspend@  Suspend\n\
@icon:restart@  Restart\n\
@icon:power@  Shutdown\n" | rofi -dmenu -i -p "Power" -lines 10 -no-fixed-num-lines)

exit_code=$?

case "$choice" in
	*Lock*) hyprlock ;;
	*Logout*) hyprctl dispatch exit ;;
	*Suspend*) systemctl suspend ;;
	*Restart*) systemctl reboot ;;
	*Shutdown*) systemctl poweroff ;;
esac

if [ "$exit_code" -ne 0 ]; then
    exec coel-main-menu
fi

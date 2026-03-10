#!/usr/bin/bash

profiles=$(powerprofilesctl list | awk '/:$/ {gsub("\\*",""); gsub(":",""); print $1}')

chosen=$(echo "$profiles" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Power Profiles")

if [ -n "$chosen" ]; then
    powerprofilesctl set "$chosen"
fi

exit_code=$?

case "$choice" in
	*Lock*) echo 6;;
	*Restart*) systemctl reboot;;
	*Shutdown*) systemctl poweroff;;
esac

if [ $exit_code -ne 0 ]; then
    # Rofi was cancelled
    ~/.coelOS-dotfiles/configs/rofi/settings.sh
    exit 0
fi

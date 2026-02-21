#!/usr/bin/env bash

choice=$(printf \
"   Lock\n\
 󰤄  Suspend\n\
   Restart\n\
 󰤆  Shutdown\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Main Menu")

case "$choice" in
	*Lock*) hyprlock;;
	*Suspend*) systemctl suspend;;
	*Restart*) systemctl reboot;;
	*Shutdown*) systemctl poweroff;;
esac

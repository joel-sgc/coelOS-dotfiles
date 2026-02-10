#!/usr/bin/env bash

choice=$(printf \
"   Lock\n\
   Restart\n\
 󰤆  Shutdown\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Main Menu")

case "$choice" in
	*Lock*) echo 6;;
	*Restart*) systemctl reboot;;
	*Shutdown*) systemctl poweroff;;
esac

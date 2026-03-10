#!/usr/bin/bash

choice=$(printf \
"   Lock\n\
 󰤄  Suspend\n\
   Restart\n\
 󰤆  Shutdown\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Power")

 exit_code=$?

case "$choice" in
	*Lock*) hyprlock;;
	*Suspend*) systemctl suspend;;
	*Restart*) systemctl reboot;;
	*Shutdown*) systemctl poweroff;;
esac

if [ $exit_code -ne 0 ]; then
    # Rofi was cancelled
    ~/.coelOS-dotfiles/configs/rofi/main-menu.sh
    exit 0
fi

#!/usr/bin/env bash
choice=$(printf \
"   Lock\n\
 Suspend\n\
   Restart\n\
 Shutdown\n" | rofi -dmenu -i -p "Power" -lines 10 -no-fixed-num-lines)

exit_code=$?

case "$choice" in
	*Lock*) hyprlock ;;
	*Suspend*) systemctl suspend ;;
	*Restart*) systemctl reboot ;;
	*Shutdown*) systemctl poweroff ;;
esac

if [ "$exit_code" -ne 0 ]; then
    exec coel-main-menu
fi


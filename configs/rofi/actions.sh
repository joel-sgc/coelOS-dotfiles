#!/usr/bin/env bash

choice=$(printf \
" 󰄀  Screenshot\n\
   Screen Record\n\
   Color\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Actions")

 exit_code=$?

case "$choice" in
	*Screenshot*) exec ~/.coelOS-dotfiles/bin/screenshot.sh;;
	*Record*) exec ~/.coelOS-dotfiles/bin/screenrecord.sh;;
	*Color*) exec hyprpicker -a;;
esac

 if [ $exit_code -ne 0 ]; then
     # Rofi was cancelled
     ~/.coelOS-dotfiles/configs/rofi/main-menu.sh
     exit 0
 fi

#!/usr/bin/env bash

choice=$(printf \
" 󰄀  Screenshot\n\
   Screen Record\n\
   Color\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Actions")

case "$choice" in
	*Screenshot*) exec ~/.coelOS-dotfiles/bin/screenshot.sh;;
	*Record*) exec ~/.coelOS-dotfiles/bin/screenrecord.sh;;
	*Color*) exec hyprpicker -a;;
esac

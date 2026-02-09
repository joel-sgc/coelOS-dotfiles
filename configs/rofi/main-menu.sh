#!/usr/bin/env bash

choice=$(printf \
" 󰀻 Programs\n\
 󱓞 Actions\n\
  Settings\n\
 󱧘 Install\n\
 󱧙 Uninstall\n\
  Update\n\
  About\n\
 󰤆 System\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Main Menu")

case "$choice" in
	*Programs*) rofi -show drun -p "Launch..." -lines 10 -no-fixed-num-lines -i;;
	*Actions*) echo 2;;
	*Settings*) exec ~/coelOS-dotfiles/configs/rofi/settings.sh;;
	*Install*) echo 4;;
	*Uninstall*) echo 5;;
	*Update*) echo 6;;
	*About*) echo 7;;
	*System*) exec ~/coelOS-dotfiles/configs/rofi/power.sh;;
esac

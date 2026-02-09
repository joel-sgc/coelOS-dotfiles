#!/usr/bin/env bash

choice=$(printf \
"  Audio\n\
 󱓞 WiFi\n\
  Bluetooth\n\
 󱧘 Power Profiles\n\
 󱧙 System Sleep\n\
  Monitors\n\
  Keybindings\n\
  Input\n\
  DNS\n\
  Security\n\
 󰤆 Config\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Main Menu")

case "$choice" in
	*Programs*) rofi -show drun -p "Launch..." -lines 10 -no-fixed-num-lines -i;;
	*Actions*) echo 2;;
	*Settings*) echo 3;;
	*Install*) echo 4;;
	*Uninstall*) echo 5;;
	*Update*) echo 6;;
	*About*) echo 7;;
	*System*) ./power.sh;;
esac

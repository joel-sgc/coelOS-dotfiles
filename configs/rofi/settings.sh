#!/usr/bin/env bash

choice=$(printf \
"  Audio\n\
 󰖩 WiFi\n\
 󰂯 Bluetooth\n\
 󱐋 Power Profiles\n\
 󰤆 System Sleep\n\
 󰍹 Monitors\n\
  Keybindings\n\
 󰍽 Input\n\
 󰱔 DNS\n\
  Security\n\
  Config\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Settings")

case "$choice" in
	*Audio*) exec alacritty --class com.joelsgc.floating -e pulseaudio;;
	*WiFi*) exec alacritty --class com.joelsgc.floating -e netpala;;
	*Bluetooth*) exec alacritty --class com.joelsgc.floating -e bluepala;;
	*Power*) echo 4;;
	*System*) echo 5;;
	*Monitors*) echo 6;;
	*Keybindings*) echo 7;;
	*Input*) echo 7;;
	*DNS*) echo 7;;
	*Security*) echo 7;;
	*Config*) ./power.sh;;
esac

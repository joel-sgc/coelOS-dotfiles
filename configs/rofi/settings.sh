#!/usr/bin/bash

choice=$(printf \
"   Audio\n\
 󰖩  WiFi\n\
 󰂯  Bluetooth\n\
 󱐋  Power Profiles\n\
 󰍹  Monitors\n\
   Keybindings\n\
 󰍽  Input\n\
 󰈷  Fingerprint\n\
   Config\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Settings")

 exit_code=$?
 
case "$choice" in
	*Audio*) exec alacritty --class com.joelsgc.floating -e pulseaudio;;
	*WiFi*) exec alacritty --class com.joelsgc.floating -e netpala;;
	*Bluetooth*) exec alacritty --class com.joelsgc.floating -e bluepala;;
	*Power\ Profiles*) ~/.coelOS-dotfiles/configs/rofi/power-profiles.sh;;
	*Monitors*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/monitors.conf;;
	*Keybindings*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/keybindings.conf;;
	*Input*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/input.conf;;
	*Fingerprint*) alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/fingerprint-enroll.sh;;
	*Config*) exec ~/.coelOS-dotfiles/configs/rofi/config.sh;;
esac

 if [ $exit_code -ne 0 ]; then
     # Rofi was cancelled
     ~/.coelOS-dotfiles/configs/rofi/main-menu.sh
     exit 0
 fi

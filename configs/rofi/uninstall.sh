#!/usr/bin/env bash

choice=$(printf \
" 󰣇  Pacman/Yay\n\
   TUI\n\
   Web App\n\
 󰈷  Fingerprint\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Uninstall")

exit_code=$?

case "$choice" in
	*Pacman\/Yay*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/pac-yay-uninstall.sh;;
	*TUI*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/tui-uninstall.sh;;
	*Web*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/webapp-uninstall.sh;;
	*Fingerprint*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/fingerprint-delete.sh;;
esac

if [ $exit_code -ne 0 ]; then
    # Rofi was cancelled
    ~/.coelOS-dotfiles/configs/rofi/main-menu.sh
    exit 0
fi

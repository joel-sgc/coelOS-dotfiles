#!/usr/bin/env bash

choice=$(printf \
" 󰣇  Pacman\n\
 󰣇  AUR\n\
   TUI\n\
   Web App\n" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Main Menu")

 exit_code=$?

case "$choice" in
	*Pacman*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/pacman-install.sh;;
	*AUR*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/yay-install.sh;;
	*TUI*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/tui-install.sh;;
	*Web*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/webapp-install.sh;;
esac

 if [ $exit_code -ne 0 ]; then
     # Rofi was cancelled
     ~/.coelOS-dotfiles/configs/rofi/main-menu.sh
     exit 0
 fi

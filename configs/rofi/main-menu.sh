#!/usr/bin/bash

choice=$(printf \
" 󰀻  Programs\n\
 󱓞  Actions\n\
   Settings\n\
 󱧘  Install\n\
 󱧙  Uninstall\n\
   Update\n\
   About\n\
 󰤆  System\n" | rofi -dmenu -p -no-fixed-num-lines -i "Main Menu")

case "$choice" in
	*Programs*) rofi -show drun -theme-str 'listview { lines: 10; }';;
	*Actions*) exec ~/.coelOS-dotfiles/configs/rofi/actions.sh;;
	*Settings*) exec ~/.coelOS-dotfiles/configs/rofi/settings.sh;;
	*Install*) exec ~/.coelOS-dotfiles/configs/rofi/install.sh;;
	*Uninstall*) exec ~/.coelOS-dotfiles/configs/rofi/uninstall.sh;;
	*Update*) exec alacritty --class com.joelsgc.floating -e ~/.coelOS-dotfiles/bin/update.sh ;;
	*About*) exec alacritty --class com.joelsgc.info -e bash -c "fastfetch; read -n1 -r";;
	*System*) exec ~/.coelOS-dotfiles/configs/rofi/power.sh;;
esac

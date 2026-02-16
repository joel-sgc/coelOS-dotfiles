#!/usr/bin/env bash

choice=$(printf \
"   Hyprland\n\
   Hyprpaper\n\
   Hyprlock\n\
   Hypridle\n\
   Autostart\n\
   Window Rules\n\
 󰤆  Look & Feel\n\
    Waybar" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Main Menu")

case "$choice" in
	*Hyprland*) exec alacritty -e micro ~/.coelOS-dotfiles/configs/hypr/hyprland.conf;;
	*Hyprpaper*) exec alacritty -e micro ~/.coelOS-dotfiles/configs/hypr/hyprpaper.conf;;
	*Hyprlock*) exec alacritty -e micro ~/.coelOS-dotfiles/configs/hypr/hyprlock.conf;;
	*Hypridle*) exec alacritty -e micro ~/.coelOS-dotfiles/configs/hypr/hypridle.conf;;
	*Autostart*) exec alacritty -e micro ~/.coelOS-dotfiles/configs/hypr/autostart.conf;;
	*Window*) exec alacritty -e micro ~/.coelOS-dotfiles/configs/hypr/window-rules.conf;;
	*Look*) exec alacritty -e micro ~/.coelOS-dotfiles/configs/hypr/look-and-feel.conf;;
	*Waybar*) exec alacritty -e micro ~/.coelOS-dotfiles/configs/waybar/config.jsonc;;
esac

#!/usr/bin/bash

choice=$(printf \
"   Hyprland\n\
   Hyprlock\n\
   Hypridle\n\
 󱓞  Autostart\n\
 󱂬  Window Rules\n\
 󰏘  Look & Feel\n\
 󰌧  Waybar" | rofi -dmenu -p -lines 10 -no-fixed-num-lines -i "Configs")

exit_code=$?

case "$choice" in
	*Hyprland*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/hyprland.conf;;
	*Hyprpaper*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/hyprpaper.conf;;
	*Hyprlock*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/hyprlock.conf;;
	*Hypridle*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/hypridle.conf;;
	*Autostart*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/autostart.conf;;
	*Window*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/window-rules.conf;;
	*Look*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/hypr/look-and-feel.conf;;
	*Waybar*) exec alacritty -e fresh ~/.coelOS-dotfiles/configs/waybar.jsonc;;
esac

if [ $exit_code -ne 0 ]; then
    # Rofi was cancelled
    ~/.coelOS-dotfiles/configs/rofi/settings.sh
    exit 0
fi

#!/usr/bin/env bash
choice=$(printf \
"   Audio\n\
 󰖩  WiFi\n\
 󰂯  Bluetooth\n\
 󱐋  Power Profiles\n\
 󰍹  Monitors\n\
   Keybindings\n\
 󰍽  Input\n\
 󰈷  Fingerprint\n\
   Config\n" | rofi -dmenu -i -p "Settings" -lines 10 -no-fixed-num-lines)

exit_code=$?

case "$choice" in
	*Audio*) exec ghostty -e pulsemixer ;;
	*WiFi*) exec coel-todo "WiFi (netpala) isn't adapted to NixOS yet." ;;
	*Bluetooth*) exec coel-todo "Bluetooth (bluepala) isn't adapted to NixOS yet." ;;
	*Power\ Profiles*) exec coel-power-profiles-menu ;;
	*Monitors*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
	*Keybindings*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
	*Input*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
	*Fingerprint*) exec coel-fingerprint-menu ;;
	*Config*) exec coel-config-menu ;;
esac

if [ "$exit_code" -ne 0 ]; then
    exec coel-main-menu
fi


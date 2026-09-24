#!/usr/bin/env bash
# @icon:<name>@ placeholders are filled with Nerd Font glyphs at build time
# (see power-menu.sh / home/icons.nix). Don't paste the glyphs in here.
choice=$(printf \
"@icon:audio@  Audio\n\
@icon:wifi@  WiFi\n\
@icon:bluetooth@  Bluetooth\n\
@icon:power-profiles@  Power Profiles\n\
@icon:monitors@  Monitors\n\
@icon:keybindings@  Keybindings\n\
@icon:input@  Input\n\
@icon:fingerprint@  Fingerprint\n\
@icon:config@  Config\n" | rofi -dmenu -i -p "Settings" -lines 10 -no-fixed-num-lines)

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

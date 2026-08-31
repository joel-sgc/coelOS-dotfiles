#!/usr/bin/env bash
choice=$(printf \
"   Hyprland\n\
   Hyprlock\n\
   Hypridle\n\
 󱓞  Autostart\n\
 󱂬  Window Rules\n\
 󰏘  Look & Feel\n\
 󰌧  Waybar\n" | rofi -dmenu -i -p "Config" -lines 10 -no-fixed-num-lines)

exit_code=$?

case "$choice" in
	*Hyprland*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
	*Hyprlock*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hypridle.nix" ;;
	*Hypridle*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hypridle.nix" ;;
	*Autostart*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
	*Window\ Rules*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
	*Look*) exec coel-todo "Look & Feel isn't broken out into its own theme file yet — styling is still deferred." ;;
	*Waybar*) exec coel-todo "Waybar isn't configured/styled yet." ;;
esac

if [ "$exit_code" -ne 0 ]; then
    exec coel-settings-menu
fi


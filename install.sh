#!/bin/bash

sudo pacman -Syu --noconfirm

pacman_packages=(
	hyprland
	hyprlock 
	hypridle 
	hyprpaper 
	waybar 
	sddm 
	fprintd 
	gnome-keyring 
	networkmanager
	base
	base-devel
	zram-generator
	alacritty
	rofi
	gtk4
	gtk4-layer-shell
	poppler-glib
	pipewire
	noto-fonts-emoji
	ttf-jetbrains-mono-nerd
	woff2-font-awesome
	git
	micro
	unzip
	btop
	eza
	fastfetch
	gum
	fzf
	wiremix
	power-profiles-daemom
	python-gobject
	grim
	slurp
	jq
	satty
	wl-clipboard
	mako
	libnotify
	gpu-screen-recorder
	v4l-utils
	xdg-desktop-portal-hyprland
	hyprpicker
)

aur_packages=(
	privacy-dots
	zen-browser-bin
	netpala
	bluepala
	wayfreeze-git
)

# Install all required pacman packages
sudo pacman -S --needed "${pacman_packages[@]}" --noconfirm

# Install yay utility
sudo pacman -S --needed git base-devel && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si

# Install all yay packages
yay -S --needed "${aur_packages[@]}" --noconfirm

# Create Pictures and Videos directories for screenshots and screenrecordings
mkdir -p ~/Pictures ~/Videos

#Edit sudoers file to allow rofi shutdown and restart
echo "%group_name ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown" | sudo EDITOR='tee -a' visudo

# Syslinks
mkdir -p ~/.config/{hypr,rofi,fastfetch,waybar}

ln -s ~/.coelOS-dotfiles/configs/hypr/hyprland.conf ~/.config/hypr/hyprland.conf #hyprland
ln -s ~/.coelOS-dotfiles/configs/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf #hyprlock
ln -s ~/.coelOS-dotfiles/configs/hypr/hypridle.conf ~/.config/hypr/hypridle.conf #hypridle

ln -s ~/.coelOS-dotfiles/configs/rofi/config.rasi ~/.config/rofi/config.rasi #rofi
ln -s ~/.coelOS-dotfiles/theme/rofi.rasi ~/.config/rofi/themes/coel-theme.rasi #rofi

ln -s ~/.coelOS-dotfiles/configs/sddm/sddm.conf /etc/sddm.conf #sddm

ln -s ~/.coelOS-dotfiles/configs/fastfetch/fastfetch.jsonc ~/.config/fastfetch/config.jsonc #Fastfetch

sudo ln -s ~/.coelOS-dotfiles/configs/waybar/config.jsonc /etc/xdg/waybar/config.json #waybar
sudo ln -s ~/.coelOS-dotfiles/configs/waybar/style.css /etc/xdg/waybar/style.css #waybar


# Services
sudo systemctl enable --now NetworkManager
sudo systemctl enable sddm
sudo systemctl enable --now gnome-keyring-daemon.service
sudo systemctl enable --now power-profiles-daemon
sudo systemctl enable --now fprintd

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
	less
	gum
	fzf
	wiremix
	power-profiles-daemon
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

mkdir -p ~/.config/rofi/theme
ln -s ~/.coelOS-dotfiles/configs/rofi/config.rasi ~/.config/rofi/config.rasi #rofi
ln -s ~/.coelOS-dotfiles/theme/rofi.rasi ~/.config/rofi/theme/coel-theme.rasi #rofi

sudo setfacl -R -m u:sddm:rx ~/.coelOS-dotfiles
sudo setfacl -m u:sddm:x ~
sudo ln -s ~/.coelOS-dotfiles/configs/sddm/sddm.conf /etc/sddm.conf #sddm
sudo ln -s ~/.coelOS-dotfiles/theme/sddm /usr/share/sddm/themes/coel-sddm #sddm

ln -s ~/.coelOS-dotfiles/configs/fastfetch/fastfetch.jsonc ~/.config/fastfetch/config.jsonc #Fastfetch

sudo rm -rf /etc/xdg/waybar/*
sudo ln -s ~/.coelOS-dotfiles/configs/waybar/config.jsonc /etc/xdg/waybar/config.jsonc #waybar
sudo ln -s ~/.coelOS-dotfiles/configs/waybar/style.css /etc/xdg/waybar/style.css #waybar


# Services
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now sddm
sudo systemctl enable --now gnome-keyring-daemon.service
sudo systemctl enable --now power-profiles-daemon
sudo systemctl enable --now fprintd

## Disable systemd-networkd
sudo systemctl disable --now systemd-networkd.service
sudo systemctl disable --now systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd.service
sudo systemctl mask systemd-networkd-wait-online.service

# networkmanager config
sudo mkdir -p /etc/NetworkManager/conf.d
sudo ln -s ~/.coelOS-dotfiles/configs/networkmanager/wifi-backend.conf /etc/NetworkManager/conf.d/wifi-backend.conf

sudo systemctl restart NetworkManager


# Fonts
mkdir -p ~/.local/share/fonts
cp ~/.coelOS-dotfiles/fonts/*.ttf ~/.local/share/fonts
fc-cache -fv

# Remove random .desktop files
usrdesktops=(
	btop
	avahi-discover
	bssh
	bvnc
	qv4l2
	qvidcao
	rofi
	rofi-theme-selector
	wiremix
	xgps
	xgpsspeed
)

for app in "${usrdesktops[@]}"; do
	sudo rm -rf "/usr/share/applications/${app}.desktop"
done

# Alias
alias ls='eza -l --header'

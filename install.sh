#!/bin/bash

sudo pacman -Syu --noconfirm

pacman_packages=(
	hyprland
	hypridle 
	hyprpaper 
	hyprlock 
	swayidle
	waybar 
	sddm 
	polkit
	polkit-kde-agent
	fprintd 
	libfprint
	pam
	gnome-keyring 
	networkmanager
	base
	base-devel
	zram-generator
	alacritty
	rofi
	wl-clipboard
	gtk4
	gtk4-layer-shell
	poppler-glib
	pipewire
	pipewire-alsa
	pipewire-pulse
	wireplumber
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
	mako
	libnotify
	gpu-screen-recorder
	v4l-utils
	xdg-desktop-portal-hyprland
	hyprpicker
	code
	github-cli
)

aur_packages=(
	privacy-dots
	zen-browser-bin
	netpala
	bluepala
	wayfreeze-git
	clipvault
)

# Install all required pacman packages
sudo pacman -S --needed "${pacman_packages[@]}" --noconfirm

# Install yay utility
sudo pacman -S --needed git base-devel && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si

# Install all yay packages
yay -S --needed "${aur_packages[@]}" --noconfirm

# Create Pictures and Videos directories for screenshots and screenrecordings
mkdir -p ~/Pictures ~/Videos

sudo visudo -cf /etc/sudoers && \
sudo grep -Fxq "$LINE" /etc/sudoers || \
echo "%group_name ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown, /sbin/suspend" | sudo EDITOR='tee -a' visudo

# Syslinks
mkdir -p ~/.config/{hypr,rofi,fastfetch,waybar}

ln -s ~/.coelOS-dotfiles/configs/hypr/hyprland.conf ~/.config/hypr/hyprland.conf #hyprland
ln -s ~/.coelOS-dotfiles/configs/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf #hyprlock
ln -s ~/.coelOS-dotfiles/configs/hypr/hypridle.conf ~/.config/hypr/hypridle.conf #hypridle
ln -s ~/.coelOS-dotfiles/configs/hypr/hyprpaper.conf ~/.config/hypr/hyprpaper.conf #hypridle

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

mkdir -p ~/.config/alacritty #alacritty
ln -s ~/.coelOS-dotfiles/configs/alacritty/alacritty.toml ~/.config/alacritty/alacritty.toml #alacritty

# Fingerprint
sudo cp ~/.coelOS-dotfiles/configs/polkit-fprint.rules /etc/polkit-1/rules.d/50-fprint.rules
sudo chown root:root /etc/polkit-1/rules.d/50-fprint.rules
sudo chmod 644 /etc/polkit-1/rules.d/50-fprint.rules
sudo systemctl restart polkit

PAM_SUDO="/etc/pam.d/sudo"
FPRINT_LINE="auth sufficient pam_fprintd.so"

if ! grep -q "^auth.*pam_fprintd.so" "$PAM_SUDO"; then
	sudo sed -i "1i $FPRINT_LINE" "$PAM_SUDO"
fi

# Suspend & Powerbutton
sudo mkdir -p /etc/systemd/logind.conf.d/
sudo mkdir -p /etc/udev/hwdb.d/
sudo ln -s ~/.coelOS-dotfiles/configs/power/logind-power.conf /etc/systemd/logind.conf.d/10-power.conf
sudo ln -s ~/.coelOS-dotfiles/configs/power/70-framework-power.hwdb /etc/udev/hwdb.d/70-framework-power.hwdb
sudo systemd-hwdb update
sudo udevadm trigger

# Services
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now power-profiles-daemon
sudo systemctl enable --now fprintd
systemctl --user enable --now pipewire pipewire-pulse wireplumber

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
sudo mkdir -p /usr/share/fonts
sudo cp ~/.coelOS-dotfiles/fonts/*.ttf /usr/share/fonts
fc-cache -fv

# Remove random .desktop files
usrdesktops=(
	btop
	avahi-discover
	bssh
	bvnc
	qv4l2
	qvidcap
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
sed -i "/alias ls=/d" ~/.bashrc
echo "alias ls='eza -l --header'" >> ~/.bashrc

sudo ln -s ~/coelOS-dotfiles/.inputrc ~/.inputrc

# Finally, enable sddm and go to desktop environment
sudo systemctl enable --now sddm

#!/bin/bash

# --- Update System ---
sudo pacman -Syu --noconfirm

pacman_packages=(
  # --- Core System & Hardware ---
  base
  base-devel
  fprintd                  # Fingerprint daemon
  libfprint                # Fingerprint library
  networkmanager
  power-profiles-daemon    # Power management
  zram-generator           # Optimized swap

  # --- Wayland & Hyprland Core ---
  hyprland
  hypridle
  hyprlock
  hyprpaper
  hyprpicker
  sddm                     # Login manager
  swayidle
  waybar                   # Status bar
  xdg-desktop-portal-hyprland

  # --- Auth & Security ---
  gnome-keyring
  pam
  polkit
  polkit-kde-agent

  # --- Audio & Media ---
  pipewire
  pipewire-alsa
  pipewire-pulse
  wireplumber
  wiremix
  v4l-utils                # Video4Linux tools

  # --- Terminal & Shell Tools ---
  alacritty
  btop
  eza                      # Modern 'ls'
  fastfetch
  fzf
  gum                      # Script interactivity
  less
  micro                    # Text editor
  unzip
  wl-clipboard
  starship                 # Fast, customizable shell prompt

  # --- Development ---
  code                     # VS Code
  git
  github-cli
  jq                       # JSON processor
  python-gobject

  # --- UI, Menus & Notifications ---
  gtk4
  gtk4-layer-shell
  libnotify
  mako                     # Notification daemon
  rofi                     # Application launcher / Power menu
  poppler-glib

  # --- Graphics & Screenshots ---
  gpu-screen-recorder
  grim                     # Screenshot tool
  slurp                    # Region selector
  satty                    # Screenshot annotation

  # --- Fonts ---
  noto-fonts-emoji
  ttf-jetbrains-mono-nerd
  woff2-font-awesome
)

aur_packages=(
  bluepala                 # Bluetooth TUI
  clipvault                # Clipboard manager
  netpala                  # Network TUI
  privacy-dots             # Camera/Mic indicators
  wayfreeze-git            # Screen freeze tool
  zen-browser-bin
)

# --- Install Pacman Packages ---
sudo pacman -S --needed "${pacman_packages[@]}" --noconfirm

# --- Install Yay (AUR Helper) ---
if ! command -v yay &> /dev/null; then
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin && makepkg -si --noconfirm
    cd .. && rm -rf yay-bin
fi

yay -S --needed "${aur_packages[@]}" --noconfirm

# --- Directory Setup ---
mkdir -p ~/Pictures ~/Videos ~/.config/{hypr,rofi/theme,fastfetch,waybar,alacritty,micro/colorschemes}

# --- Sudoers NOPASSWD for Power Actions ---
# This checks if the specific poweroff permission exists before adding it
SUDO_LINE="%wheel ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown, /sbin/suspend"
sudo grep -qxF "$SUDO_LINE" /etc/sudoers || echo "$SUDO_LINE" | sudo EDITOR='tee -a' visudo

# --- Symlinks (Using -sf to allow overwriting/updating) ---
ln -sf ~/.coelOS-dotfiles/configs/hypr/hyprland.conf ~/.config/hypr/hyprland.conf
ln -sf ~/.coelOS-dotfiles/configs/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf
ln -sf ~/.coelOS-dotfiles/configs/hypr/hypridle.conf ~/.config/hypr/hypridle.conf
ln -sf ~/.coelOS-dotfiles/configs/hypr/hyprpaper.conf ~/.config/hypr/hyprpaper.conf
ln -sf ~/.coelOS-dotfiles/configs/rofi/config.rasi ~/.config/rofi/config.rasi
ln -sf ~/.coelOS-dotfiles/theme/rofi.rasi ~/.config/rofi/theme/coel-theme.rasi
ln -sf ~/.coelOS-dotfiles/configs/fastfetch/fastfetch.jsonc ~/.config/fastfetch/config.jsonc
ln -sf ~/.coelOS-dotfiles/configs/alacritty/alacritty.toml ~/.config/alacritty/alacritty.toml

# --- Micro setup ---
ln -sf ~/.coelOS-dotfiles/theme/micro/micro-theme.micro ~/.config/micro/colorschemes/CoelOS.micro
ln -sf ~/.coelOS-dotfiles/configs/micro/settings.json ~/.config/micro/settings.json

# --- SDDM Setup ---
# Permissions for SDDM to access themes in your home dir
sudo setfacl -R -m u:sddm:rx ~/.coelOS-dotfiles
sudo setfacl -m u:sddm:x ~
sudo ln -sf ~/.coelOS-dotfiles/configs/sddm/sddm.conf /etc/sddm.conf
sudo ln -sf ~/.coelOS-dotfiles/theme/sddm /usr/share/sddm/themes/coel-sddm

# --- Waybar System-wide Symlinks ---
sudo rm -rf /etc/xdg/waybar/*
sudo ln -sf ~/.coelOS-dotfiles/configs/waybar/config.jsonc /etc/xdg/waybar/config.jsonc
sudo ln -sf ~/.coelOS-dotfiles/configs/waybar/style.css /etc/xdg/waybar/style.css

# --- Fingerprint & Polkit ---
sudo cp ~/.coelOS-dotfiles/configs/polkit-fprint.rules /etc/polkit-1/rules.d/50-fprint.rules
sudo chown root:root /etc/polkit-1/rules.d/50-fprint.rules
sudo chmod 644 /etc/polkit-1/rules.d/50-fprint.rules

# --- Starship Prompt ---
sudo ln -sf ~/.coelOS-dotfiles/configs/starship.toml ~/.config/starship.toml 

# Add fingerprint to PAM if not present
PAM_SUDO="/etc/pam.d/sudo"
FPRINT_LINE="auth sufficient pam_fprintd.so"
grep -q "pam_fprintd.so" "$PAM_SUDO" || sudo sed -i "1i $FPRINT_LINE" "$PAM_SUDO"

# --- Power & Framework Buttons ---
sudo mkdir -p /etc/systemd/logind.conf.d/ /etc/udev/hwdb.d/
sudo ln -sf ~/.coelOS-dotfiles/configs/power/logind-power.conf /etc/systemd/logind.conf.d/10-power.conf
sudo ln -sf ~/.coelOS-dotfiles/configs/power/70-framework-power.hwdb /etc/udev/hwdb.d/70-framework-power.hwdb
sudo systemd-hwdb update
sudo udevadm trigger

# --- Services Configuration ---
sudo systemctl enable --now NetworkManager fprintd power-profiles-daemon
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# Ensure systemd-networkd doesn't conflict with NetworkManager
sudo systemctl disable --now systemd-networkd.service systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd.service systemd-networkd-wait-online.service

# NetworkManager Backend Config
sudo mkdir -p /etc/NetworkManager/conf.d
sudo ln -sf ~/.coelOS-dotfiles/configs/networkmanager/wifi-backend.conf /etc/NetworkManager/conf.d/wifi-backend.conf

# --- Fonts ---
sudo mkdir -p /usr/share/fonts/local
sudo cp ~/.coelOS-dotfiles/fonts/*.ttf /usr/share/fonts/local/ 2>/dev/null || true
fc-cache -fv

# --- Cursor ---
mkdir -p ~/.local/share/icons
tar -xf ~/.coelOS-dotfiles/theme/oreo-spark-light-pink-cursors.tar.gz
mv oreo_spark_light_pink_cursors/ ~/.local/share/icons/oreo_spark_light_pink_cursors

# --- Cleanup .desktop clutter ---
usrdesktops=(btop avahi-discover bssh bvnc qv4l2 qvidcap rofi rofi-theme-selector wiremix xgps xgpsspeed)
for app in "${usrdesktops[@]}"; do
  sudo rm -f "/usr/share/applications/${app}.desktop"
done

# --- Shell Environment (.bashrc & .inputrc) ---
# Update alias
grep -q "alias ls=" ~/.bashrc && sed -i "/alias ls=/d" ~/.bashrc
echo "alias ls='eza -l --header'" >> ~/.bashrc

# Case-insensitive completion
[[ -f ~/.inputrc ]] || touch ~/.inputrc
grep -qxF "set completion-ignore-case on" ~/.inputrc || echo "set completion-ignore-case on" >> ~/.inputrc

# --- Starship Prompt Setup ---
if ! grep -q 'eval "$(starship init bash)"' ~/.bashrc; then
  echo 'eval "$(starship init bash)"' >> ~/.bashrc
fi

# --- Zen Browser Setup ---
# - Custom Profile -
[ -d "$HOME/.config/zen/CoelOS" ] || {
  zen-browser --no-remote -CreateProfile "CoelOS $HOME/.config/zen/CoelOS"
  zen-browser --headless &>/dev/null & sleep 2; kill $!
  printf "%s\nDefault=CoelOS\nLocked=1\n\n[Profile0]\nName=CoelOS\nPath=CoelOS\nIsRelative=1\nDefault=1\n\n[General]\nStartWithLastProfile=1\nVersion=2\n" "$(grep -m1 '^\[Install' "$HOME/.config/zen/profiles.ini")" > "$HOME/.config/zen/profiles.ini"
}

# - Profile Customization -
sudo mkdir -p /etc/zen/policies
sudo ln -sf ~/.coelOS-dotfiles/configs/zen-browser/user.js ~/.config/zen/CoelOS/user.js
sudo ln -sf ~/.coelOS-dotfiles/configs/zen-browser/policies.json /etc/zen/policies/policies.json

# --- Finalize ---
sudo systemctl restart NetworkManager
sudo systemctl enable --now sddm

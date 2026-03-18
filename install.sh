#!/bin/bash

# ==============================================================================
# 1. INITIALIZATION & UI FRAMEWORK
# ==============================================================================

# Request sudo privileges upfront
echo -e "\033[1;34m[~]\033[0m Enter your password to begin the unattended setup..."
sudo -v

# Create a temporary sudoers rule to prevent mid-script password prompts
TEMP_SUDOERS="/etc/sudoers.d/99_temp_coelos_install"
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "$TEMP_SUDOERS" > /dev/null
sudo chmod 0440 "$TEMP_SUDOERS"

# TRAP: This guarantees the temporary sudoers file is deleted the moment the 
# script exits, errors out, or is interrupted (Ctrl+C). It keeps your system secure.
trap 'sudo rm -f "$TEMP_SUDOERS"' EXIT

# --- UI Colors & Variables ---
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

LOG_FILE="coelos_install_$(date +%s).log"
echo "=== CoelOS Setup Log Started at $(date) ===" > "$LOG_FILE"

print_header() {
  clear
  echo -e "${BOLD}${BLUE}=========================================${NC}"
  echo -e "${BOLD}         CoelOS System Installer         ${NC}"
  echo -e "${BOLD}${BLUE}=========================================${NC}\n"
}

print_section() {
  echo -e "${BLUE}┌── ${BOLD}$1${NC}"
  echo -e "${BLUE}│${NC}"
}

run_task() {
  local task_name="$1"
  local command="$2"
  
  ((TOTAL_COUNT++))
  echo -ne "${BLUE}├──${NC} ${YELLOW}[~]${NC} $task_name..."
  echo -e "\n[EXECUTING]: $task_name" >> "$LOG_FILE"
  
  if eval "$command" >> "$LOG_FILE" 2>&1; then
    ((SUCCESS_COUNT++))
    echo -e "\r${BLUE}├──${NC} ${GREEN}[✔]${NC} $task_name                                        "
  else
    ((FAIL_COUNT++))
    echo -e "\r${BLUE}├──${NC} ${RED}[✘]${NC} $task_name (Failed)                               "
  fi
}

close_section() {
  echo -e "${BLUE}└── ${GREEN}Done${NC}\n"
}

print_summary() {
  echo -e "${BOLD}${BLUE}=========================================${NC}"
  echo -e "${BOLD}              Setup Summary              ${NC}"
  echo -e "${BOLD}${BLUE}=========================================${NC}"
  echo -e "  Total Tasks:  ${TOTAL_COUNT}"
  echo -e "  ${GREEN}Successful:   ${SUCCESS_COUNT}${NC}"
    
  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "  ${RED}Failed:       ${FAIL_COUNT}${NC}"
    echo -e "\n  ${YELLOW}Please check ${BOLD}$LOG_FILE${NC}${YELLOW} for error details.${NC}"
  else
    echo -e "  ${RED}Failed:       ${FAIL_COUNT}${NC}"
    echo -e "\n  ${GREEN}All tasks completed successfully!${NC}"
  fi
  echo -e "${BOLD}${BLUE}=========================================${NC}\n"
}

# ==============================================================================
# 2. PACKAGE LISTS
# ==============================================================================

pacman_packages=(
  base base-devel fprintd libfprint networkmanager power-profiles-daemon 
  zram-generator plymouth hyprland hypridle hyprlock hyprpicker swww sddm 
  waybar xdg-desktop-portal-hyprland gnome-keyring pam polkit polkit-gnome 
  pipewire pipewire-alsa pipewire-pulse wireplumber wiremix v4l-utils 
  alacritty btop eza fastfetch fzf gum less unzip wl-clipboard 
  starship git github-cli jq python-gobject swayosd brightnessctl gtk4 
  gtk4-layer-shell libnotify mako rofi rofi-emoji poppler-glib gpu-screen-recorder 
  grim slurp satty noto-fonts-emoji ttf-jetbrains-mono-nerd woff2-font-awesome 
  ttf-firacode-nerd thunar thunar-volman thunar-archive-plugin tumbler gvfs 
  qemu-desktop libvirt dnsmasq dmidecode virt-manager
  tailscale kdeconnect chromium gimp zsh
)

aur_packages=(
  netpala bluepala clipvault privacy-dots wayfreeze-git 
  zen-browser-bin visual-studio-code-bin fresh-editor-bin
)

# ==============================================================================
# 3. HELPER FUNCTIONS FOR TASKS
# ==============================================================================

install_pacman_pkgs() {
  sudo pacman -S --needed "${pacman_packages[@]}" --noconfirm
}

install_yay() {
  if ! command -v yay &> /dev/null; then
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin && makepkg -si --noconfirm
    cd .. && rm -rf yay-bin
  fi
}

install_aur_pkgs() {
  yay -S --needed "${aur_packages[@]}" --noconfirm
}

setup_sudoers() {
  SUDO_LINE="%wheel ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown, /sbin/suspend"
  sudo grep -qxF "$SUDO_LINE" /etc/sudoers || echo "$SUDO_LINE" | sudo EDITOR='tee -a' visudo
}

setup_symlinks() {
  ln -sf ~/.coelOS-dotfiles/configs/hypr/hyprland.conf ~/.config/hypr/hyprland.conf
  ln -sf ~/.coelOS-dotfiles/configs/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf
  ln -sf ~/.coelOS-dotfiles/configs/hypr/hypridle.conf ~/.config/hypr/hypridle.conf
  ln -sf ~/.coelOS-dotfiles/configs/hypr/hyprpaper.conf ~/.config/hypr/hyprpaper.conf
  ln -sf ~/.coelOS-dotfiles/configs/rofi/config.rasi ~/.config/rofi/config.rasi
  ln -sf ~/.coelOS-dotfiles/theme/rofi.rasi ~/.config/rofi/theme/coel-theme.rasi
  ln -sf ~/.coelOS-dotfiles/configs/fastfetch.jsonc ~/.config/fastfetch/config.jsonc
  ln -sf ~/.coelOS-dotfiles/configs/alacritty.toml ~/.config/alacritty/alacritty.toml
  ln -sf ~/.coelOS-dotfiles/theme/swayosd.css ~/.config/swayosd/style.css
  ln -sf ~/.coelOS-dotfiles/theme/mako ~/.config/mako/config
  ln -sf ~/.coelOS-dotfiles/configs/netpala.toml ~/.config/netpala/config.toml
  ln -sf ~/.coelOS-dotfiles/configs/starship.toml ~/.config/starship.toml 
  ln -sf ~/.coelOS-dotfiles/theme/btop.theme ~/.config/btop/themes/CoelOS.theme
  ln -sf ~/.coelOS-dotfiles/configs/btop.conf ~/.config/btop/btop.conf  
  ln -sf ~/.coelOS-dotfiles/configs/fresh.json ~/.config/fresh/config.json  
}

setup_bootloader() {
  LIMINE_CONF=$(find "/boot" -type f -name limine.conf 2>/dev/null)
  FOUND_UUID=$(grep -oP 'PARTUUID=\K[^:]+' "$LIMINE_CONF")
  sudo sed "s/{{ROOT_UUID}}/$FOUND_UUID/g" ~/.coelOS-dotfiles/configs/limine.conf | sudo tee "$LIMINE_CONF" > /dev/null

  sudo mkdir -p /usr/share/plymouth/themes/
  sudo cp -R ~/.coelOS-dotfiles/configs/plymouth /usr/share/plymouth/themes/coelos
  sudo sed -i '/^HOOKS=.*plymouth/! s/\bencrypt\b/plymouth encrypt/' /etc/mkinitcpio.conf
  sudo mkinitcpio -P
  sudo plymouth-set-default-theme -R coelos
}

setup_sddm() {
  sudo setfacl -R -m u:sddm:rx ~/.coelOS-dotfiles
  sudo setfacl -m u:sddm:x ~
  sudo ln -sf ~/.coelOS-dotfiles/configs/sddm.conf /etc/sddm.conf
  sudo ln -sf ~/.coelOS-dotfiles/theme/sddm /usr/share/sddm/themes/coel-sddm
}

setup_username_configs() {
  sed -i 's|\$HOME|'"$HOME"'|g' ~/.coelOS-dotfiles/configs/sddm.conf
  sed -i 's|\$HOME|'"$HOME"'|g' ~/.coelOS-dotfiles/theme/waybar.css
}

setup_waybar() {
  sudo rm -rf /etc/xdg/waybar/*
  sudo ln -sf ~/.coelOS-dotfiles/configs/waybar.jsonc /etc/xdg/waybar/config.jsonc
  sudo ln -sf ~/.coelOS-dotfiles/theme/waybar.css /etc/xdg/waybar/style.css
}

setup_fprint() {
  sudo cp ~/.coelOS-dotfiles/configs/polkit-fprint.rules /etc/polkit-1/rules.d/50-fprint.rules
  sudo chown root:root /etc/polkit-1/rules.d/50-fprint.rules
  sudo chmod 644 /etc/polkit-1/rules.d/50-fprint.rules

  PAM_SUDO="/etc/pam.d/sudo"
  FPRINT_LINE="auth sufficient pam_fprintd.so"
  grep -q "pam_fprintd.so" "$PAM_SUDO" || sudo sed -i "1i $FPRINT_LINE" "$PAM_SUDO"
}

setup_power_fw() {
  sudo mkdir -p /etc/systemd/logind.conf.d/ /etc/udev/hwdb.d/
  sudo ln -sf ~/.coelOS-dotfiles/configs/power/logind-power.conf /etc/systemd/logind.conf.d/10-power.conf
  sudo ln -sf ~/.coelOS-dotfiles/configs/power/70-framework-power.hwdb /etc/udev/hwdb.d/70-framework-power.hwdb
  sudo systemd-hwdb update
  sudo udevadm trigger
}

setup_services() {
  sudo systemctl enable --now NetworkManager fprintd power-profiles-daemon tailscaled virtqemud.socket virtstoraged.socket virtnetworkd.socket virtnodedevd
  systemctl --user enable --now pipewire pipewire-pulse wireplumber
  sudo systemctl disable --now systemd-networkd.service systemd-networkd-wait-online.service
  sudo systemctl mask systemd-networkd.service systemd-networkd-wait-online.service
  
  sudo mkdir -p /etc/NetworkManager/conf.d
  sudo ln -sf ~/.coelOS-dotfiles/configs/networkmanager.conf /etc/NetworkManager/conf.d/wifi-backend.conf
  sudo tailscale set --operator=$USER
}

setup_theming() {
  # Wallpapers
  for file in ~/.coelOS-dotfiles/theme/wallpapers/*; do
    if [ -f "$file" ]; then
      filename=$(basename "$file")
      ln -sf "$file" "$HOME/Pictures/Wallpapers/$filename"
    fi
  done

  # Cursor & GTK
  mkdir -p ~/.local/share/icons
  sudo ln -sf ~/.coelOS-dotfiles/theme/oreo_spark_light_pink_cursors/ ~/.local/share/icons/oreo_spark_light_pink_cursors
  sudo cp -R ~/.coelOS-dotfiles/theme/gtk ~/.themes/CoelOS
}

cleanup_desktops() {
  local apps=(
    btop avahi-discover bssh bvnc qv4l2 qvidcap rofi rofi-theme-selector 
    wiremix xgps xgpsspeed thunar-bulk-rename thunar-settings thunar-volman-settings
    org.kde.kdeconnect.nonplasma org.kde.kdeconnect.sms
  )
  for app in "${apps[@]}"; do
    sudo rm -f "/usr/share/applications/${app}.desktop"
  done
}

setup_shell() {
  ln -sf ~/.coelOS-dotfiles/configs/.zshrc ~/.zshrc
  sudo usermod -s $(which zsh) $USER
}

setup_zen() {
  zen-browser --no-remote -CreateProfile "CoelOS $HOME/.config/zen/CoelOS"
  zen-browser --headless &>/dev/null & sleep 2; kill $!
  printf "%s\nDefault=CoelOS\nLocked=1\n\n[Profile0]\nName=CoelOS\nPath=CoelOS\nIsRelative=1\nDefault=1\n\n[General]\nStartWithLastProfile=1\nVersion=2\n" "$(grep -m1 '^\[Install' "$HOME/.config/zen/profiles.ini")" > "$HOME/.config/zen/profiles.ini"
  sudo mkdir -p /etc/zen/policies
  sudo ln -sf ~/.coelOS-dotfiles/configs/zen-browser/user.js ~/.config/zen/CoelOS/user.js
  sudo ln -sf ~/.coelOS-dotfiles/configs/zen-browser/policies.json /etc/zen/policies/policies.json
}

finalize() {
  chmod +x ~/.coelOS-dotfiles/bin/swww-cycle.sh
  
  if ! journalctl -u NetworkManager -b -g supplicant >/dev/null 2>&1; then
      sudo systemctl restart NetworkManager
  fi
  sudo systemctl enable sddm
  sudo reboot
}

# ==============================================================================
# 4. EXECUTION
# ==============================================================================

print_header

print_section "System Updates & Package Installation"
run_task "Updating package databases (pacman -Syu)" "sudo pacman -Syu --noconfirm"
run_task "Installing standard repository packages" "install_pacman_pkgs"
run_task "Checking and installing Yay (AUR Helper)" "install_yay"
run_task "Installing AUR packages" "install_aur_pkgs"
close_section

print_section "Directory Setup & Base Permissions"
run_task "Creating local directory structure" "mkdir -p ~/Pictures/Wallpapers ~/Videos ~/.themes ~/.config/{zen/CoelOS,hypr,btop/themes,rofi/theme,fastfetch,waybar,alacritty,swayosd,mako,netpala,fresh}"
run_task "Configuring sudoers NOPASSWD for power actions" "setup_sudoers"
close_section

print_section "Configuration & Dotfiles"
run_task "Applying dotfile symlinks" "setup_symlinks"
run_task "Configuring shell environment (Bash/Starship)" "setup_shell"
run_task "Configuring Waybar system-wide" "setup_waybar"
close_section

print_section "Security, Boot & Authentication"
run_task "Configuring Bootloader (Limine) & LUKS" "setup_bootloader"
run_task "Setting up fingerprint daemon & Polkit rules" "setup_fprint"
run_task "Configuring user account" "setup_username_configs"
close_section

print_section "Hardware & Services"
run_task "Configuring power profiles & Framework buttons" "setup_power_fw"
run_task "Managing system and network services" "setup_services"
close_section

print_section "Desktop Environment & Theming"
run_task "Configuring SDDM Login Manager" "setup_sddm"
run_task "Applying GTK themes, cursors, and wallpapers" "setup_theming"
run_task "Cleaning up unused .desktop application files" "cleanup_desktops"
close_section

print_section "Application Configurations"
run_task "Setting up Zen Browser custom profile" "setup_zen"
run_task "Finalizing system states" "finalize"
close_section

print_summary

{ inputs, config, pkgs, ... }:

{
  ##############################################################################
  # Identity
  ##############################################################################

  home.username = "joelsgc";
  home.homeDirectory = "/home/joelsgc";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  ##############################################################################
  # Module Imports
  ##############################################################################

  imports = [
    # Programs
    ./home/zsh.nix
    ./home/micro.nix
    ./home/ghostty.nix
    ./home/development.nix
    ./home/zen-browser.nix
    ./home/hyprland.nix

    # Services / integrations
    ./home/globalprotect.nix
    ./home/flatpak.nix
    inputs.opencode.homeManagerModules.default
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  ##############################################################################
  # Services
  ##############################################################################

  services.opencode = {
    enable = true;
    package = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
  };

  ##############################################################################
  # Packages
  ##############################################################################

  home.packages = [
    # Clipboard (Wayland + X11)
    pkgs.wl-clipboard
    pkgs.xclip

    # CLI / shell tools
    pkgs.eza
    pkgs.starship

    # Desktop apps
    pkgs.orca-slicer
    pkgs.vscode-fhs
    pkgs.stremio-linux-shell
    pkgs.waybar
    pkgs.rofi
    # pkgs.spotify

    # Fonts
    pkgs.nerd-fonts.fira-code

    # Networking / VPN
    pkgs.sshfs
    pkgs.wireguard-tools
    pkgs.proton-vpn

    # Security tools
    pkgs.john
  ];

  ##############################################################################
  # Session Variables
  ##############################################################################

  home.sessionVariables = {
    TERMINAL = "ghostty";
    EDITOR = "micro";
    VISUAL = "micro";
    GTK_THEME = "Adwaita:dark";
  };
}

{ inputs, config, pkgs, lib, ... }:

{
  ##############################################################################
  # Identity
  ##############################################################################

  home.username = "joelsgc";
  home.homeDirectory = "/home/joelsgc";
  home.stateVersion = "26.05";

  # Declaratively manage KWin script and shortcuts
  xdg.configFile."kglobalshortcutsrc".source = ./home/kglobalshortcutsrc;
  xdg.dataFile."kwin/scripts/normalize-minimize/metadata.json".source = ./home/kwin-scripts/normalize-minimize/metadata.json;
  xdg.dataFile."kwin/scripts/normalize-minimize/contents/code/main.js".source = ./home/kwin-scripts/normalize-minimize/contents/code/main.js;

  # Use a Home Manager activation script to safely enable the KWin script.
  # This modifies the kwinrc file in place, which is the correct approach.
  home.activation.enableNormalizeMinimize = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kconfig}/bin/kwriteconfig6 --file kwinrc --group Plugins --key normalize-minimizeEnabled true
  '';

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
    ./home/mako.nix
    ./home/hypridle.nix
    ./home/wallpaper.nix
    ./home/swayosd.nix
    ./home/clipboard.nix
    ./home/rofi.nix

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
    pkgs.steam-run # run non-NixOS/dynamically-linked binaries: steam-run <cmd>

    # Desktop apps
    pkgs.orca-slicer
    pkgs.vscode-fhs
    pkgs.stremio-linux-shell
    pkgs.waybar
    # pkgs.spotify

    # Fonts
    pkgs.nerd-fonts.fira-code

    # Networking / VPN
    pkgs.sshfs
    pkgs.wireguard-tools
    pkgs.proton-vpn

    # Security tools
    pkgs.john

    # Hyprland session utilities (media keys, notifications)
    pkgs.playerctl
    pkgs.libnotify
  ];

  ##############################################################################
  # Session Variables
  ##############################################################################

  home.sessionVariables = {
    TERMINAL = "ghostty";
    EDITOR = "micro";
    VISUAL = "micro";
    GTK_THEME = "Adwaita:dark";

    # nixpkgs.config.allowUnfree in configuration.nix only applies to the
    # pkgs instance NixOS builds for this flake — plain `nix build/shell/run
    # nixpkgs#...` instantiates a fresh nixpkgs straight from the registry
    # and never sees it. This env var is the actual designed escape hatch for
    # that case (flakes intentionally ignore ~/.config/nixpkgs/config.nix).
    NIXPKGS_ALLOW_UNFREE = "1";
  };
}

{
  inputs,
  pkgs,
  ...
}:

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
    ./home/fresh.nix
    ./home/quickshell.nix
    ./home/kicad.nix
    ./home/ghostty.nix
    ./home/development.nix
    ./home/zen-browser.nix
    ./home/hyprland.nix
    ./home/mako.nix
    ./home/hypridle.nix
    ./home/wallpaper.nix
    ./home/theme.nix
    ./home/fastfetch.nix
    ./home/swayosd.nix
    ./home/clipboard.nix
    ./home/rofi.nix
    ./home/waybar.nix
    ./home/desktop-entries.nix
    ./home/udiskie.nix
    ./home/poweralertd.nix
    ./home/kanshi.nix
    ./home/kde-window-shortcuts.nix
    ./home/kde-shortcuts.nix
    ./home/kde-wallpaper.nix
    ./home/kde-theme.nix
    ./home/qt-theme.nix

    # Services / integrations
    ./home/globalprotect.nix
    ./home/flatpak.nix
    inputs.opencode.homeManagerModules.default
    inputs.nix-flatpak.homeManagerModules.nix-flatpak

    # Terminal-friendly NetworkManager TUI (github:joel-sgc/netpala).
    inputs.netpala.homeManagerModules.default
    ./home/netpala.nix

    inputs.bluepala.homeManagerModules.default
    ./home/bluepala.nix
  ];

  ##############################################################################
  # Services
  ##############################################################################

  services.opencode = {
    enable = true;
    package = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true; # Automatically hooks into Zsh
    nix-direnv.enable = true; # Heavily speeds up evaluation through caching
  };

  ##############################################################################
  # Packages
  ##############################################################################

  home.packages = with pkgs; [
    # Clipboard (Wayland + X11)
    wl-clipboard
    xclip

    # CLI / shell tools
    eza
    starship
    devenv
    steam-run # run non-NixOS/dynamically-linked binaries: steam-run <cmd>

    # Desktop apps
    vscode
    stremio-linux-shell
    gimp
    # spotify

    # Fonts
    nerd-fonts.fira-code # rofi + ghostty (home/rofi.nix, home/ghostty.nix)
    noto-fonts-color-emoji # without this, coel-emoji-picker has nothing to actually render

    # Networking / VPN
    sshfs
    wireguard-tools
    proton-vpn

    # Security tools
    john

    # Hyprland session utilities (media keys, notifications)
    playerctl
    libnotify

    # General utility -- cross-referenced against a couple of well-known
    # Hyprland rices' package lists (JaKooLit, HyDE), both include it as a
    # baseline dependency
    imagemagick
  ];

  ##############################################################################
  # Session Variables
  ##############################################################################

  home.sessionVariables = {
    TERMINAL = "ghostty";
    EDITOR = "micro";
    VISUAL = "micro";
    GTK_THEME = "Adwaita:dark";

    # Makes Electron apps (VS Code) and Firefox-based browsers (Zen) render
    # natively on Wayland instead of falling back to XWayland. Matters more
    # than usual here since XWayland has no real fractional-scaling support
    # -- at the monitor's 1.17 scale factor, XWayland-rendered apps look
    # pixelated. Benefits both Hyprland and Plasma (also Wayland-native), so
    # this is global rather than Hyprland-only.
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";

    # nixpkgs.config.allowUnfree in configuration.nix only applies to the
    # pkgs instance NixOS builds for this flake — plain `nix build/shell/run
    # nixpkgs#...` instantiates a fresh nixpkgs straight from the registry
    # and never sees it. This env var is the actual designed escape hatch for
    # that case (flakes intentionally ignore ~/.config/nixpkgs/config.nix).
    NIXPKGS_ALLOW_UNFREE = "1";
  };
}

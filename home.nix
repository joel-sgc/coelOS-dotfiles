{ inputs, config, pkgs, ... }:

{
  home.username = "joelsgc";
  home.homeDirectory = "/home/joelsgc";

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  imports = [
  	./home/micro.nix
		./home/zen-browser.nix
		./home/ghostty.nix
		./home/zsh.nix
		./home/git.nix
  ];

  home.packages = [
  	pkgs.wl-clipboard # The clipboard provider for Wayland
  	pkgs.xclip        # The clipboard provider for X11
  	pkgs.eza
    pkgs.starship
    pkgs.orca-slicer
    pkgs.sshfs
  ];

  home.sessionVariables = {
  	TERMINAL = "ghostty";
  	EDITOR = "micro";
  	VISUAL = "micro";
  	GTK_THEME = "Adwaita:dark";
  };
}

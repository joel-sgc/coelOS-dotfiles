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
    inputs.opencode.homeManagerModules.default
  ];

  services.opencode = {
    enable = true;
    package = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
  };

  home.packages = [
  	pkgs.wl-clipboard # The clipboard provider for Wayland
  	pkgs.xclip        # The clipboard provider for X11
  	pkgs.eza
    pkgs.starship
    pkgs.orca-slicer
    pkgs.nerd-fonts.fira-code
    pkgs.vscode-fhs
    pkgs.sshfs
  ];

  home.sessionVariables = {
  	TERMINAL = "ghostty";
  	EDITOR = "micro";
  	VISUAL = "micro";
  	GTK_THEME = "Adwaita:dark";
  };
}

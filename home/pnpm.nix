{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nodejs
    pnpm
  ];

  home.sessionVariables = {
    PNPM_HOME = "$HOME/.local/share/pnpm";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.local/share/pnpm"
  ];

  xdg.configFile."pnpm/rc".text = ''
    global-bin-dir=$HOME/.local/bin
    global-dir=$HOME/.local/share/pnpm/global
    state-dir=$HOME/.local/state/pnpm
    cache-dir=$HOME/.cache/pnpm
  '';
}

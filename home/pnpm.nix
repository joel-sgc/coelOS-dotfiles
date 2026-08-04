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
    "$HOME/.local/share/pnpm/bin"
  ];

  home.file.".npmrc".text = ''
    global-bin-dir=/home/joelsgc/.local/bin
    global-dir=/home/joelsgc/.local/share/pnpm/global
    state-dir=/home/joelsgc/.local/state/pnpm
    cache-dir=/home/joelsgc/.cache/pnpm
  '';
}

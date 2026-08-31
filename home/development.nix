{ pkgs, ... }:

{
  imports = [
    ./git.nix
    ./pnpm.nix
  ];

  home.packages = with pkgs; [
    uv

    go
    gcc
    
    arduino-ide
    python3
    
    espeak
  ];
}

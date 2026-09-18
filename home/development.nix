{ pkgs, ... }:

{
  imports = [
    ./git.nix
    ./pnpm.nix
  ];

  home.packages = with pkgs; [
    python3
    uv

    go
    gcc
    
    arduino-ide
    arduino-cli
    espeak
    
    (vscode.fhsWithPackages (ps: with ps; [ systemd libusb1 stdenv.cc.cc ]))
  ];  
}

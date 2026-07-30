{ config, pkgs, ... }:

{
  programs.ghostty = {
    enable = true;
    settings = {
      keybind = [
      ];
    };
  };
}

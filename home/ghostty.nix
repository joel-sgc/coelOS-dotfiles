{ config, pkgs, ... }:

{
  programs.ghostty = {
    enable = true;
    settings = {
      keybind = [
        "ctrl+t=new_tab"
        "ctrl+w=close_tab"
      ];
    };
  };
}

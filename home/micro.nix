{ config, pkgs, ... }:

{
  programs.micro = {
    enable = true;

    settings = {
      autosave = true;
      tabsize = 2;
    };
  };
}

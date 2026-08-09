{ config, pkgs, ... }:

{
  # Auto-switches monitor layout profiles based on which outputs are
  # currently connected (e.g. laptop panel alone vs. docked with an
  # external monitor). Its module already respects wayland.systemd.target
  # correctly out of the box, no override needed.
  #
  # No profiles defined yet -- kanshi runs fine with none (just idles),
  # but doesn't do anything useful until you add one. To add one: run
  # `hyprctl monitors` to get the real current output names/descriptions,
  # then add something like:
  #
  # services.kanshi.settings = [
  #   {
  #     profile.name = "docked";
  #     profile.outputs = [
  #       { criteria = "eDP-1"; mode = "2256x1504@60"; position = "0,0"; }
  #       { criteria = "DP-2"; mode = "1600x900@60"; position = "2256,0"; }
  #     ];
  #   }
  #   {
  #     profile.name = "laptop-only";
  #     profile.outputs = [
  #       { criteria = "eDP-1"; mode = "2256x1504@60"; position = "0,0"; }
  #     ];
  #   }
  # ];
  services.kanshi.enable = true;
}

{ config, pkgs, ... }:

{
  # Volume/brightness OSD popup. Matches the old Arch/Omarchy setup
  # (swayosd-server + swayosd-client), bound to the media keys in
  # home/hyprland.nix.
  #
  # Brightness control needs write access to /sys/class/backlight, which the
  # swayosd-shipped udev rule grants to the `video` group — see
  # services.udev.packages and the user's extraGroups in configuration.nix.
  #
  # Not wiring up swayosd's libinput backend (a *system*-level service for
  # reacting to raw CapsLock/ScrollLock key events) since we bind the media
  # keys directly through Hyprland instead — one less root-level daemon.
  services.swayosd.enable = true;
}

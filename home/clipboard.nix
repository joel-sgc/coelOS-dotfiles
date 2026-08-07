{ config, pkgs, ... }:

{
  # Clipboard history. The old Arch config used a self-built tool
  # (clipvault); cliphist is the standard Wayland equivalent and needs no
  # extra packaging. History is plain text via `cliphist list`, so it's
  # accessible from anywhere (including piping into micro), not just rofi.
  # Picker is bound to SUPER+V in home/hyprland.nix.
  services.cliphist.enable = true;
}

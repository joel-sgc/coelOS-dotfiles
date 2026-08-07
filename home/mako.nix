{ config, pkgs, ... }:

{
  # Notification daemon. Only started via home/hyprland.nix's exec-once, so
  # it never launches during a Plasma session (Plasma has its own). No
  # styling yet — defaults are fine for now, theming comes later.
  services.mako.enable = true;
}

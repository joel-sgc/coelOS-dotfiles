{ ... }:

let
  theme = import ./theme/everforest.nix;
in
{
  # Notification daemon. Only started via home/hyprland.nix's exec-once, so
  # it never launches during a Plasma session (Plasma has its own).
  services.mako = {
    enable = true;
    settings = {
      background-color = "${theme.bg0}e6";
      text-color = theme.fg;
      border-color = theme.green;
      border-size = 2;
      border-radius = 8;
      default-timeout = 5000;
      layer = "overlay";
      anchor = "top-right";

      "urgency=critical".border-color = theme.red;
    };
  };
}

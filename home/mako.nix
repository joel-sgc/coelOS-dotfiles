{ ... }:

let
  theme = import ./theme/onedark.nix;
in
{
  # Notification daemon. Only started via home/hyprland.nix's exec-once, so
  # it never launches during a Plasma session (Plasma has its own).
  services.mako = {
    enable = true;
    settings = {
      background-color = "${theme.bg}e6";
      text-color = theme.fg;
      border-color = theme.blue;
      border-size = 2;
      border-radius = 8;
      default-timeout = 5000;
      layer = "overlay";
      anchor = "top-right";

      # theme.error (their explicit "error" role, #f44747), not theme.red
      # (coral, #ef596f) -- coral is their emphasis/accent color, not their
      # failure-state color.
      "urgency=critical".border-color = theme.error;
    };
  };
}

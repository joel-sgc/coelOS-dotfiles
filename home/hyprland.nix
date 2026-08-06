{ config, pkgs, ... }:

{
  # Phase 1 of the Hyprland migration: bare compositor, just enough to log
  # in, open a terminal, and move between workspaces. Bar, launcher,
  # notifications, lock/idle, portals, and applets land in later phases.
  wayland.windowManager.hyprland = {
    enable = true;
    # Use the Hyprland package/session registered by programs.hyprland.enable
    # in configuration.nix instead of installing a second copy here.
    package = null;

    settings = {
      monitor = [ ",preferred,auto,auto" ];

      "$terminal" = "ghostty";
      "$mainMod" = "SUPER";

      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
      };

      bind =
        [
          "$mainMod, Return, exec, $terminal"
          "$mainMod, Q, killactive"
          "$mainMod SHIFT, M, exit"
          "$mainMod, V, togglefloating"
          "$mainMod, left, movefocus, l"
          "$mainMod, right, movefocus, r"
          "$mainMod, up, movefocus, u"
          "$mainMod, down, movefocus, d"
        ]
        ++ builtins.concatLists (
          builtins.genList (
            i:
            let
              ws = toString (i + 1);
            in
            [
              "$mainMod, ${ws}, workspace, ${ws}"
              "$mainMod SHIFT, ${ws}, movetoworkspace, ${ws}"
            ]
          ) 9
        );
    };
  };
}

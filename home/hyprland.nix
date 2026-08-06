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
		configType = "hyprlang";

    settings = {
      monitor = [ ",preferred,auto,1" ];

      "$terminal" = "ghostty";
      "$mainMod" = "SUPER";

      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
      };

      input = {
        touchpad = {
          natural_scroll = true;
        };
      };

      # workspace_swipe/workspace_swipe_fingers were removed upstream in 0.51 —
      # gestures are now declared with the top-level `gesture` directive instead.
      gesture = [
        "3, horizontal, workspace"
      ];

      exec-once = [
        "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
        "${pkgs.waybar}/bin/waybar"
      ];

      bind =
        [
          "$mainMod, T, exec, $terminal"
          "$mainMod, space, exec, ${pkgs.rofi}/bin/rofi -show drun"
          "$mainMod, Q, killactive"
          "$mainMod SHIFT, M, exit"
          "$mainMod, F, togglefloating"
          "$mainMod, left, movefocus, l"
          "$mainMod, right, movefocus, r"
          "$mainMod, up, movefocus, u"
          "$mainMod, down, movefocus, d"
        ]
        ++ builtins.concatLists (
          builtins.genList (
            i:
            let
              ws = i + 1;
              key = if ws == 10 then "0" else toString ws;
              wsStr = toString ws;
            in
            [
              "$mainMod, ${key}, workspace, ${wsStr}"
              "$mainMod SHIFT, ${key}, movetoworkspace, ${wsStr}"
            ]
          ) 10
        );
    };
  };
}

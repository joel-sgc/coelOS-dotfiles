{ config, pkgs, ... }:

{
  # Scope every Wayland user service (hypridle, swayosd, awww, cliphist, ...)
  # to Hyprland's own session target instead of the generic
  # graphical-session.target. Plasma's session also activates the generic
  # target, so leaving this at the default would start these services during
  # a Plasma login too. See home/hypridle.nix, home/swayosd.nix,
  # home/wallpaper.nix, home/clipboard.nix.
  wayland.systemd.target = "hyprland-session.target";

  # Mirrors configuration.nix's system-level xdg.portal.config. This is a
  # *separate* option namespace under home-manager (writes to
  # ~/.config/xdg-desktop-portal/), which the Hyprland module would normally
  # wire up on its own via its `configPackages` default — except that only
  # triggers when `package != null`, and we set that to null above. Left
  # unset, home-manager warns and the per-desktop split only exists at the
  # system level (still correct via XDG config fallback, but better to have
  # both agree explicitly).
  xdg.portal.config = {
    hyprland.default = [ "hyprland" "gtk" ];
    kde.default = [ "kde" ];
    common.default = [ "gtk" ];
  };

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
          clickfinger_behavior = 1;
        };
      };

      # workspace_swipe/workspace_swipe_fingers were removed upstream in 0.51 —
      # gestures are now declared with the top-level `gesture` directive instead.
      gesture = [
        "3, horizontal, workspace"
      ];

      windowrule = [
        {
          # Ignore maximize requests from all apps.
          name = "suppress-maximize-events";
          "match:class" = ".*";
          suppress_event = "maximize";
        }
        {
          # Works around an XWayland dragging bug.
          name = "fix-xwayland-drags";
          "match:class" = "^$";
          "match:title" = "^$";
          "match:xwayland" = true;
          "match:float" = true;
          "match:fullscreen" = false;
          "match:pin" = false;
          no_focus = true;
        }
      ];

      exec-once = [
        "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
        "${pkgs.waybar}/bin/waybar"
        "${pkgs.mako}/bin/mako"
        # Blocks logind's default hardware-power-key handling so the
        # XF86PowerOff bind below (-> coel-power-menu) is what actually
        # fires, instead of an immediate shutdown racing the menu.
        "${pkgs.systemd}/bin/systemd-inhibit --what=handle-power-key --who=Hyprland --why='Custom power menu' --mode=block sleep infinity"
      ];

      bind =
        [
          "$mainMod, T, exec, $terminal"
          "$mainMod, space, exec, ${config.programs.rofi.finalPackage}/bin/rofi -show drun"
          "$mainMod SHIFT, space, exec, coel-main-menu"
          "$mainMod, period, exec, coel-emoji-picker"
          "$mainMod, L, exec, ${pkgs.hyprlock}/bin/hyprlock"
          "$mainMod, W, killactive"
          "$mainMod, M, exit"
          "$mainMod, F, togglefloating"
          "$mainMod SHIFT, F, fullscreen"
          "$mainMod, left, movefocus, l"
          "$mainMod, right, movefocus, r"
          "$mainMod, up, fullscreen, 1"
          "$mainMod, down, fullscreen, 1"
          "$mainMod SHIFT, left, resizeactive, 10"
          "$mainMod SHIFT, right, resizeactive, -10"
          "$mainMod SHIFT, up, resizeactive, 0 -10"
          "$mainMod SHIFT, down, resizeactive, 0 10"
          "$mainMod, V, exec, ${pkgs.cliphist}/bin/cliphist list | ${config.programs.rofi.finalPackage}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy"
          ", XF86AudioRaiseVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume raise"
          ", XF86AudioLowerVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume lower"
          ", XF86AudioMute, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle"
          ", XF86MonBrightnessUp, exec, ${pkgs.swayosd}/bin/swayosd-client --brightness raise"
          ", XF86MonBrightnessDown, exec, ${pkgs.swayosd}/bin/swayosd-client --brightness lower"
          ", Print, exec, coel-screenshot"
          ", XF86PowerOff, exec, coel-power-menu"
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

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      bindl = [
        ", XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous && ${pkgs.libnotify}/bin/notify-send -a swayosd -h string:x-canonical-private-synchronous:track-controls 'Previous Track'"
        ", XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next && ${pkgs.libnotify}/bin/notify-send -a swayosd -h string:x-canonical-private-synchronous:track-controls 'Next Track'"
        ", XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause && ${pkgs.libnotify}/bin/notify-send -a swayosd -h string:x-canonical-private-synchronous:track-controls 'Play/Pause'"
        ", XF86AudioPause, exec, ${pkgs.playerctl}/bin/playerctl play-pause && ${pkgs.libnotify}/bin/notify-send -a swayosd -h string:x-canonical-private-synchronous:track-controls 'Play/Pause'"
      ];
    };
  };
}

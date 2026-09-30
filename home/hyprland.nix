{
  pkgs,
  lib,
  ...
}:

let
  theme = import ./theme/onedark.nix;
  strip = lib.removePrefix "#";
in
{
  # Scope every Wayland user service (hypridle, swayosd, awww, cliphist, ...)
  # to Hyprland's own session target instead of the generic
  # graphical-session.target. Plasma's session also activates the generic
  # target, so leaving this at the default would start these services during
  # a Plasma login too. See home/hypridle.nix, home/swayosd.nix,
  # home/wallpaper.nix, home/clipboard.nix.
  wayland.systemd.target = "hyprland-session.target";

  # Mirrors configuration.nix's system-level xdg.portal.config in
  # home-manager's own separate option namespace (~/.config/xdg-desktop-portal/),
  # since the Hyprland module only wires this up itself when `package != null`,
  # and that's set to null below.
  xdg.portal.config = {
    hyprland.default = [
      "hyprland"
      "gtk"
    ];
    kde.default = [ "kde" ];
    common.default = [ "gtk" ];
  };

  # The user-profile portal service looks in this per-user profile's dir,
  # not the system one configuration.nix's xdg.portal.extraPortals
  # populates -- without gtk's package in home.packages too, its .portal
  # file never reaches here, so "gtk" in the `default` list above would be
  # a no-op. (xdg-desktop-portal-hyprland needs no such entry -- the
  # Hyprland module adds it on its own.)
  home.packages = [ pkgs.xdg-desktop-portal-gtk ];

  wayland.windowManager.hyprland = {
    enable = true;
    # Use the Hyprland package/session registered by programs.hyprland.enable
    # in configuration.nix instead of installing a second copy here.
    package = null;
    configType = "hyprlang";

    # Defaults to false. Without it, apps that rely on the standard XDG
    # autostart mechanism (a .desktop file in ~/.config/autostart or
    # /etc/xdg/autostart) to launch themselves at login never do -- Plasma
    # and GNOME both honor this automatically, Hyprland doesn't unless told.
    systemd.enableXdgAutostart = true;

    settings = {
      monitor = [
        "eDP-1,2256x1504@59.999,0x0,1"
        "DP-9, preferred, 0x-1080, 1"
      ];

      # Also set here (not just home.sessionVariables) per the Hyprland
      # wiki's own recommendation -- Hyprland's env directive guarantees
      # this reaches everything it execs, rather than depending on how
      # session-startup environment inheritance happens to work.
      env = [
        "NIXOS_OZONE_WL,1"
        "MOZ_ENABLE_WAYLAND,1"
        # Deliberately set only here, not globally (home.sessionVariables)
        # -- see home/qt-theme.nix for why. Gives Qt6 apps under Hyprland
        # (e.g. hyprland-share-picker) a real color source instead of
        # falling back to plain light Qt defaults, without ever touching
        # a separate Plasma session.
        "QT_QPA_PLATFORMTHEME,qt6ct"
      ];

      "$terminal" = "ghostty";
      "$mainMod" = "SUPER";

      general = {
        gaps_in = 4;
        gaps_out = "8, 20, 20, 20";
        border_size = 2;

        # Blue -> yellow gradient on focus, matching the primary/secondary/
        # error scheme in home/theme.nix -- red is reserved for errors
        # (theme.error), not general emphasis. Muted comment-grey when idle.
        "col.active_border" = "rgba(${strip theme.blue}ee) rgba(${strip theme.yellow}ee) 45deg";
        "col.inactive_border" = "rgba(${strip theme.comment}aa)";
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

      decoration = {
        rounding = 8;
      };

      windowrule = [
        {
          # `ghostty --class=com.joelsgc.floating -e <cmd>` opens a one-off
          # utility terminal (fingerprint enroll/delete, coel-update,
          # pulsemixer, btop, ...) that should float instead of tiling.
          # Sized in pixels (ghostty's own cell-based window-width/height is
          # documented as buggy under GTK decorations) -- 1556x925 measures
          # to ~140x41 cols at this system's font (FiraCode Nerd Font Mono,
          # size 10), comfortable for btop-style TUI panes.
          name = "float-utility-terminal";
          "match:class" = "^com\\.joelsgc\\.floating$";
          float = true;
          size = "1556 925";
        }
        {
          # Same idea, but for the fastfetch "About" popup.
          name = "float-info-terminal";
          "match:class" = "^com\\.joelsgc\\.info$";
          float = true;
          size = "832 502";
        }
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
        "${pkgs.mako}/bin/mako"
        # Blocks logind's default hardware-power-key handling so the
        # XF86PowerOff bind below (-> coel-power-menu) is what actually
        # fires, instead of an immediate shutdown racing the menu.
        "${pkgs.systemd}/bin/systemd-inhibit --what=handle-power-key --who=Hyprland --why='Custom power menu' --mode=block sleep infinity"
        # Random wallpaper on every login (home/wallpaper.nix; Plasma's
        # equivalent is the XDG autostart entry in home/kde-wallpaper.nix).
        # The script itself retries for a few seconds in case it races the
        # awww daemon's systemd-user startup.
        "coel-random-wallpaper"
        # -c straight at this repo (not ~/.config/quickshell) so quickshell
        # hot-reloads on edit while developing the panel; home-manager's
        # deployed copy doesn't.
        #
        # QML_DISABLE_DISK_CACHE=1: Qt's compiled-QML bytecode cache is
        # keyed loosely enough that it can serve a stale compile straight
        # through a kill+relaunch. The config here is small enough that
        # losing the cache's JIT-skip benefit isn't a real cost.
        "env QML_DISABLE_DISK_CACHE=1 ${pkgs.quickshell}/bin/quickshell -c ~/.nixos/home/quickshell"
      ];

      bind = [
        "$mainMod, T, exec, $terminal"
        # `quickshell ipc call` talks to the IpcHandler in Launcher.qml --
        # needs `-p ~/.nixos/home/quickshell` (a path) to target the
        # instance launched above with `-c` (a named XDG config); with no
        # path/config flag it looks for the default
        # ~/.config/quickshell/shell.qml instance instead and silently
        # no-ops.
        "$mainMod, space, exec, ${pkgs.quickshell}/bin/quickshell ipc -p ~/.nixos/home/quickshell call launcher toggle"
        "$mainMod SHIFT, space, exec, ${pkgs.quickshell}/bin/quickshell ipc -p ~/.nixos/home/quickshell call launcher toggle"
        # Opens the launcher restricted to emoji-only search
        # (LauncherPanel.qml's searchScope) -- emoji is search-only, no chip.
        "$mainMod, period, exec, ${pkgs.quickshell}/bin/quickshell ipc -p ~/.nixos/home/quickshell call launcher openEmoji"
        # The real Quickshell lock screen (home/quickshell/lock/), same
        # repo-path reasoning as home/hypridle.nix's lockCmd. hyprlock's own
        # config is left in place, unused, as a manual fallback -- see
        # home/hypridle.nix's comment on programs.hyprlock.
        "$mainMod, L, exec, ${pkgs.quickshell}/bin/quickshell -p ~/.nixos/home/quickshell/lock-real-shell.qml"
        "$mainMod, W, killactive"
        "$mainMod, M, exit"
        "$mainMod, B, exec, coel-random-wallpaper"
        "$mainMod, F, togglefloating"
        "$mainMod SHIFT, F, fullscreen"
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"
        "$mainMod SHIFT, left, resizeactive, 10"
        "$mainMod SHIFT, right, resizeactive, -10"
        "$mainMod SHIFT, up, resizeactive, 0 -10"
        "$mainMod SHIFT, down, resizeactive, 0 10"
        # Launcher's own clipboard tab (LauncherPanel.qml) -- real preview
        # (formatted text / actual images), reachable via openClipboard()'s
        # IpcHandler function.
        "$mainMod, V, exec, ${pkgs.quickshell}/bin/quickshell ipc -p ~/.nixos/home/quickshell call launcher openClipboard"
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

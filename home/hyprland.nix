{
  pkgs,
  lib,
  config,
  ...
}:

let
  theme = import ./theme/onedark.nix;
  strip = lib.removePrefix "#";

  # Restarts the panel (F4). Kills every instance of the main shell config
  # by command line -- `quickshell kill` only finds instances it can match
  # by config name, and misses orphans -- then relaunches. Deliberately
  # scoped to the `-c <repo>/home/quickshell` panel: the lock screen and
  # other `-p` instances must survive. The `[q]` keeps pkill/pgrep from
  # matching this script's own command line.
  restartQuickshell = pkgs.writeShellScript "restart-quickshell" ''
    pattern='[q]uickshell -c .*/home/quickshell$'
    pkill -f "$pattern"
    for _ in $(seq 1 20); do
      pgrep -f "$pattern" >/dev/null || break
      sleep 0.1
    done
    pkill -9 -f "$pattern"
    QML_DISABLE_DISK_CACHE=1 exec ${pkgs.quickshell}/bin/quickshell -c ~/.nixos/home/quickshell
  '';
in
{
  # Scope every Wayland user service (hypridle, swayosd, awww, cliphist, ...)
  # to Hyprland's own session target instead of the generic
  # graphical-session.target. See home/hypridle.nix, home/swayosd.nix,
  # home/wallpaper.nix, home/clipboard.nix.
  wayland.systemd.target = "hyprland-session.target";

  # Home Manager only creates this when wayland.windowManager.hyprland.
  # systemd.enable is true, which UWSM replaces. Same definition, started
  # by exec-once below.
  systemd.user.targets.hyprland-session.Unit = {
    Description = "Hyprland compositor session";
    BindsTo = [ "graphical-session.target" ];
    Wants = [ "graphical-session-pre.target" ];
    After = [ "graphical-session-pre.target" ];
  };

  # Hyprland-only env for systemd-started services (portals etc.), which
  # never see Hyprland's own `env =` lines. env-hyprland is sourced by
  # UWSM for Hyprland sessions.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export NIXOS_OZONE_WL=1
    export MOZ_ENABLE_WAYLAND=1
    export QT_QPA_PLATFORMTHEME=qt6ct
    export QT_PLUGIN_PATH=${config.home.profileDirectory}/lib/qt-6/plugins
  '';

  # Mirrors configuration.nix's system-level xdg.portal.config in
  # home-manager's own separate option namespace (~/.config/xdg-desktop-portal/),
  # since the Hyprland module only wires this up itself when `package != null`,
  # and that's set to null below.
  xdg.portal.config = {
    hyprland.default = [
      "hyprland"
      "gtk"
    ];
    common.default = [ "gtk" ];
  };

  # The user-profile portal service looks in this per-user profile's dir,
  # not the system one configuration.nix's xdg.portal.extraPortals
  # populates -- without gtk's package in home.packages too, its .portal
  # file never reaches here, so "gtk" in the `default` list above would be
  # a no-op. (xdg-desktop-portal-hyprland needs no such entry -- the
  # Hyprland module adds it on its own.)
  home.packages = [ pkgs.xdg-desktop-portal-gtk ];

  # The workspace grid logic that hyprland.lua requires (a plain module, with unit
  # tests in home/hyprland/grid_test.lua). Lives next to hyprland.lua.
  xdg.configFile."hypr/grid.lua".source = ./hyprland/grid.lua;

  # Start every rebuild with an empty compiled-QML cache, so a stale compile can
  # never survive an edit; the first login after a rebuild recompiles once, the
  # ones after it start from the cache.
  home.activation.clearQuickshellQmlCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rm -rf "$HOME/.cache/quickshell/qmlcache"
  '';

  wayland.windowManager.hyprland = {
    enable = true;
    # Use the Hyprland package/session registered by programs.hyprland.enable
    # in configuration.nix instead of installing a second copy here.
    package = null;

    # The whole config is Lua (home/hyprland/hyprland.lua): Hyprland reads
    # ~/.config/hypr/hyprland.lua instead of a hyprland.conf. Lua is what lets the
    # workspace grid (rows that remember their column, vertical/sideways slide)
    # live inside Hyprland instead of in an external script. The placeholders in
    # the file are filled in here.
    configType = "lua";

    # UWSM owns the systemd session (env import, graphical-session.target,
    # XDG autostart via wayland-session-xdg-autostart@.target). Home
    # Manager's own integration would double-start all of that.
    systemd.enable = false;

    extraConfig =
      lib.replaceStrings
        [
          "@quickshell@"
          "@systemd@"
          "@profileDir@"
          "@restartQuickshell@"
          "@blue@"
          "@yellow@"
          "@comment@"
        ]
        [
          "${pkgs.quickshell}"
          "${pkgs.systemd}"
          "${config.home.profileDirectory}"
          "${restartQuickshell}"
          (strip theme.blue)
          (strip theme.yellow)
          (strip theme.comment)
        ]
        (builtins.readFile ./hyprland/hyprland.lua);
  };
}

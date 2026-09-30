{
  config,
  pkgs,
  lib,
  ...
}:

let
  theme = import ./theme/onedark.nix;

  # Walks through every surface this theme touches so a palette change can be
  # sanity-checked in one go instead of hunting down each app by hand.
  themeTest = pkgs.writeShellApplication {
    name = "coel-theme-test";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.hyprlock
      pkgs.rofi
    ];
    text = builtins.readFile ./theme/theme-test.sh;
  };
in
{
  # Verified against libadwaita's real named colors, which modern (3.24+)
  # GTK3 Adwaita also reads for consistency with GTK4. GTK reads these two
  # paths itself, live, on every app launch -- no `gtk.enable` needed for the
  # override mechanism itself, just the files being present.
  xdg.configFile = {
    "gtk-3.0/gtk.css".text = ''
      @define-color accent_color ${theme.blue};
      @define-color accent_fg_color ${theme.bg};
      @define-color accent_bg_color ${theme.blue};

      # Primary/secondary/error scheme: blue+yellow are the primary duo
      # (matching home/hyprland.nix's border gradient), green is secondary,
      # and error/destructive use theme.error (the dedicated failure-state
      # red, #f44747 -- not theme.red/coral, the emphasis/accent color).
      # These three were previously undefined here, so GTK/libadwaita apps
      # fell back to upstream's default green/yellow/red instead.
      @define-color success_color ${theme.green};
      @define-color success_bg_color ${theme.green};
      @define-color success_fg_color ${theme.bg};
      @define-color warning_color ${theme.yellow};
      @define-color warning_bg_color ${theme.yellow};
      @define-color warning_fg_color ${theme.bg};
      @define-color error_color ${theme.error};
      @define-color error_bg_color ${theme.error};
      @define-color error_fg_color ${theme.bg};
      @define-color destructive_color ${theme.error};
      @define-color destructive_bg_color ${theme.error};
      @define-color destructive_fg_color ${theme.bg};

      @define-color window_bg_color ${theme.bg};
      @define-color window_fg_color ${theme.fg};
      @define-color headerbar_bg_color ${theme.bg};
      @define-color headerbar_fg_color ${theme.fg};
      @define-color popover_bg_color ${theme.bg};
      @define-color popover_fg_color ${theme.fg};
      @define-color view_bg_color ${theme.surface};
      @define-color view_fg_color ${theme.fg};
      @define-color card_bg_color ${theme.surface};
      @define-color card_fg_color ${theme.fg};
      @define-color sidebar_bg_color @window_bg_color;
      @define-color sidebar_fg_color @window_fg_color;
      @define-color sidebar_border_color @window_bg_color;
      @define-color sidebar_backdrop_color @window_bg_color;
    '';
    "gtk-4.0/gtk.css".text = config.xdg.configFile."gtk-3.0/gtk.css".text;
  };

  # Qt theming is intentionally left to KDE/Plasma's native platform theme
  # (plasma-integration) here -- an earlier qt5ct/qt6ct setup
  # (QT_QPA_PLATFORMTHEME=qt5ct) bypassed that and crashed the shell to a
  # black screen (KWin/plasmashell couldn't resolve the QtQuickControls2
  # style). The custom One Dark palette lives on via the GTK overrides
  # above and the Plasma color scheme (home/kde-theme.nix) instead.

  home.packages = [ themeTest ];
}

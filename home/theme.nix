{ config, pkgs, lib, ... }:

let
  theme = import ./theme/everforest.nix;

  qtctColors = pkgs.writeText "qtct-colors.conf" ''
    [ColorScheme]
    active_colors=${theme.fg}, ${theme.bg1}, #ffffff, #cacaca, #9f9f9f, #b8b8b8, ${theme.fg}, #ffffff, ${theme.fg}, ${theme.bg0}, ${theme.bg0}, ${theme.bg_dim}, ${theme.bg_green}, ${theme.green}, ${theme.blue}, ${theme.green}, ${theme.bg1}, ${theme.bg_dim}, ${theme.bg1}, ${theme.fg}, ${theme.blue}
    disabled_colors=${theme.fg}, ${theme.bg1}, #ffffff, #cacaca, #9f9f9f, #b8b8b8, ${theme.fg}, #ffffff, ${theme.fg}, ${theme.bg0}, ${theme.bg0}, ${theme.bg_dim}, ${theme.bg_green}, ${theme.green}, ${theme.blue}, ${theme.green}, ${theme.bg1}, ${theme.bg_dim}, ${theme.bg1}, ${theme.fg}, ${theme.blue}
    inactive_colors=${theme.fg}, ${theme.bg1}, #ffffff, #cacaca, #9f9f9f, #b8b8b8, ${theme.fg}, #ffffff, ${theme.fg}, ${theme.bg0}, ${theme.bg0}, ${theme.bg_dim}, ${theme.bg_green}, ${theme.green}, ${theme.blue}, ${theme.green}, ${theme.bg1}, ${theme.bg_dim}, ${theme.bg1}, ${theme.fg}, ${theme.blue}
  '';

  # Walks through every surface this theme touches so a palette change can be
  # sanity-checked in one go instead of hunting down each app by hand.
  themeTest = pkgs.writeShellApplication {
    name = "coel-theme-test";
    runtimeInputs = [ pkgs.libnotify pkgs.hyprlock ];
    text = ''
      echo "== Ghostty palette (reading this in Ghostty confirms it) =="
      for i in $(seq 0 15); do printf "\033[48;5;%sm  \033[0m" "$i"; done
      echo
      echo

      echo "== Mako =="
      notify-send -a "CoelOS" "Theme Test" "Normal notification -- border should be Everforest green."
      sleep 2
      notify-send -a "CoelOS" -u critical "Theme Test" "Critical notification -- border should be Everforest red."
      sleep 1
      echo

      echo "== Rofi =="
      printf "Row one\nRow two\nRow three\n" | ${config.programs.rofi.finalPackage}/bin/rofi -dmenu -i -p "Theme Test (Esc to close)"
      echo

      echo "== Hyprland window borders =="
      echo "Compare this window's border against an unfocused one (Super+arrow to switch focus)."
      echo

      read -r -p "Test hyprlock too? Screen will lock, you'll need your password to get back in. [y/N] " ans
      case "$ans" in
        [yY]*) hyprlock ;;
        *) echo "Skipped hyprlock." ;;
      esac
    '';
  };
in
{
  # Verified against libadwaita's real named colors, which modern (3.24+)
  # GTK3 Adwaita also reads for consistency with GTK4. GTK reads these two
  # paths itself, live, on every app launch -- no `gtk.enable` needed for the
  # override mechanism itself, just the files being present.
  xdg.configFile = {
    "gtk-3.0/gtk.css".text = ''
      @define-color accent_color ${theme.green};
      @define-color accent_fg_color ${theme.bg0};
      @define-color accent_bg_color ${theme.green};
      @define-color window_bg_color ${theme.bg0};
      @define-color window_fg_color ${theme.fg};
      @define-color headerbar_bg_color ${theme.bg0};
      @define-color headerbar_fg_color ${theme.fg};
      @define-color popover_bg_color ${theme.bg0};
      @define-color popover_fg_color ${theme.fg};
      @define-color view_bg_color ${theme.bg1};
      @define-color view_fg_color ${theme.fg};
      @define-color card_bg_color ${theme.bg1};
      @define-color card_fg_color ${theme.fg};
      @define-color sidebar_bg_color @window_bg_color;
      @define-color sidebar_fg_color @window_fg_color;
      @define-color sidebar_border_color @window_bg_color;
      @define-color sidebar_backdrop_color @window_bg_color;
    '';
    "gtk-4.0/gtk.css".text = config.xdg.configFile."gtk-3.0/gtk.css".text;
  };

  # qt5ct/qt6ct give Qt5 and Qt6 apps a configurable platform theme; without
  # this they'd fall back to whatever GTK style is on PATH (often ugly) or
  # plain Fusion. QT_QPA_PLATFORMTHEME is set to "qt5ct" specifically (not
  # "qt6ct") because that's what home-manager's own qt.nix module does for
  # `platformTheme.name = "qtct"` -- qt6ct's plugin answers to that same
  # name for compatibility, so one env var covers both.
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "adwaita-dark";
    qt5ctSettings.Appearance = {
      custom_palette = true;
      color_scheme_path = "${qtctColors}";
    };
    qt6ctSettings.Appearance = {
      custom_palette = true;
      color_scheme_path = "${qtctColors}";
    };
  };

  home.packages = [ themeTest ];
}

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
    ];
    text = ''
      echo "== Ghostty palette (reading this in Ghostty confirms it) =="
      for i in $(seq 0 15); do printf "\033[48;5;%sm  \033[0m" "$i"; done
      echo
      echo

      echo "== Mako =="
      notify-send -a "CoelOS" "Theme Test" "Normal notification -- border should be One Dark blue."
      sleep 2
      notify-send -a "CoelOS" -u critical "Theme Test" "Critical notification -- border should be One Dark error red."
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
      @define-color accent_color ${theme.blue};
      @define-color accent_fg_color ${theme.bg};
      @define-color accent_bg_color ${theme.blue};
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
  # (plasma-integration) here. The old qt5ct/qt6ct setup (QT_QPA_PLATFORMTHEME=qt5ct)
  # bypassed that and broke Plasma: KWin/plasmashell then couldn't resolve the
  # QtQuickControls2 styles (module "breeze"/"adwaita-dark" is not installed),
  # crashing the shell to a black screen. The custom One Dark palette lives on
  # via the GTK overrides above and the Plasma color scheme instead.

  home.packages = [ themeTest ];
}

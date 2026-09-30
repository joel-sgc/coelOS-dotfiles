{
  config,
  pkgs,
  lib,
  ...
}:

let
  theme = import ./theme/onedark.nix;

  # QPalette color roles in colorScheme = "#ff" + hex, matching qt6ct's
  # own #AARRGGBB format (verified against a real bundled scheme,
  # colors/darker.conf, shipped by the qt6ct package itself).
  argb = hex: "#ff" + (lib.removePrefix "#" hex);

  # Order is QPalette::ColorRole's own declared order (Qt6's qpalette.h),
  # which is what qt6ct iterates when reading/writing these lists. This
  # build predates Qt 6.6's added `Accent` role (qt6ct's own shipped scheme
  # files only have 21 entries, not 22), so it's left out here too.
  roles = [
    "WindowText"
    "Button"
    "Light"
    "Midlight"
    "Dark"
    "Mid"
    "Text"
    "BrightText"
    "ButtonText"
    "Base"
    "Window"
    "Shadow"
    "Highlight"
    "HighlightedText"
    "Link"
    "LinkVisited"
    "AlternateBase"
    "NoRole"
    "ToolTipBase"
    "ToolTipText"
    "PlaceholderText"
  ];

  active = {
    WindowText = theme.fg;
    Button = theme.surface;
    Light = theme.surface;
    Midlight = theme.surface;
    Dark = theme.bg;
    Mid = theme.comment;
    Text = theme.fg;
    BrightText = theme.fg;
    ButtonText = theme.fg;
    Base = theme.bg;
    Window = theme.bg;
    Shadow = theme.bg;
    Highlight = theme.blue;
    HighlightedText = theme.bg;
    Link = theme.blue;
    LinkVisited = theme.purple;
    AlternateBase = theme.surface;
    NoRole = theme.fg;
    ToolTipBase = theme.surface;
    ToolTipText = theme.fg;
    PlaceholderText = theme.comment;
  };

  # Same as active, just dimmed on the roles that actually read as
  # "disabled" in a real UI (text/highlight-ish roles) -- structural/base
  # roles (Base, Window, Button, ...) stay the same so disabled widgets
  # don't get a different background, only greyed-out content.
  disabled = active // {
    WindowText = theme.comment;
    Text = theme.comment;
    ButtonText = theme.comment;
    Highlight = theme.comment;
    HighlightedText = theme.comment;
    Link = theme.comment;
    LinkVisited = theme.comment;
    NoRole = theme.comment;
    ToolTipText = theme.comment;
    PlaceholderText = theme.comment;
  };

  inactive = active;

  renderRow = set: lib.concatStringsSep ", " (map (r: argb set.${r}) roles);

  colorSchemePath = "${config.xdg.configHome}/qt6ct/colors/coelos-onedark.conf";
in
{
  # qt6ct provides both the config GUI and the actual Qt6 platform-theme
  # plugin (QT_QPA_PLATFORMTHEME=qt6ct below) that reads qt6ct.conf.
  #
  # Why this exists: hyprland-share-picker (xdg-desktop-portal-hyprland's
  # screen-share picker) is a Qt6 app, rendering in plain light Qt defaults
  # under Hyprland since Plasma's plasma-integration normally supplies
  # colors for free and Hyprland has no equivalent.
  #
  # QT_QPA_PLATFORMTHEME is set in home/hyprland.nix's own `env=` list, NOT
  # globally -- setting it globally (home.sessionVariables) is what broke
  # Plasma before: applied everywhere, Plasma's own session picked it up
  # too and couldn't resolve its QQC2 style anymore (see home/theme.nix's
  # comment). Hyprland's `env=` only reaches processes it execs itself, so
  # it can never reach a separate Plasma session.
  home.packages = [ pkgs.kdePackages.qt6ct ];

  xdg.configFile = {
    "qt6ct/qt6ct.conf".text = ''
      [Appearance]
      style=Fusion
      icon_theme=Papirus
      custom_palette=true
      color_scheme_path=${colorSchemePath}
    '';

    "qt6ct/colors/coelos-onedark.conf".text = ''
      [ColorScheme]
      active_colors=${renderRow active}
      disabled_colors=${renderRow disabled}
      inactive_colors=${renderRow inactive}
    '';
  };
}

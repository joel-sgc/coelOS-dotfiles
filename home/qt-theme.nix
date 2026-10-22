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
  # screen-share picker) and Dolphin are Qt6 apps that render in plain
  # light Qt defaults without a platform theme.
  #
  # QT_QPA_PLATFORMTHEME is set in home/hyprland.nix's own `env=` list and
  # uwsm env file.
  #
  # QT_QPA_PLATFORMTHEME alone isn't enough for any KDE Frameworks app
  # (Dolphin, etc.) -- their own Nix wrapper bakes in a QT_PLUGIN_PATH from
  # just their own build closure, which never includes this package's
  # plugin. home/hyprland.nix's own QT_PLUGIN_PATH (pointed at the
  # home-manager profile's merged plugin dir, where installing this
  # package via home.packages already symlinks libqt6ct.so to) is what
  # actually makes it discoverable -- see that file's comment.
  #
  # Papirus is the icon theme qt6ct.conf names below (Dolphin's file &
  # folder icons; the same one Nautilus gets implicitly under GTK). `color`
  # bakes the folder tint in at *build* time: nixpkgs' papirus-icon-theme
  # derivation runs `papirus-folders -C ${color}` itself before the result
  # becomes an immutable store path -- it can't be changed at runtime.
  # "blue" is the closest preset to theme.blue (papirus-folders only
  # supports a fixed named palette, not arbitrary hex).
  home.packages = [
    pkgs.kdePackages.qt6ct
    (pkgs.papirus-icon-theme.override { color = "blue"; })
  ];

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

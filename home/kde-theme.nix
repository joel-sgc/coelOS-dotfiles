{ pkgs, lib, ... }:

let
  theme = import ./theme/onedark.nix;

  # Tiny hex -> "R,G,B" converter -- KDE .colorscheme files use
  # comma-separated decimal RGB triplets, not hex. No dependency on any
  # particular nixpkgs lib.strings helper existing; just a lookup table.
  hexDigits = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    a = 10;
    b = 11;
    c = 12;
    d = 13;
    e = 14;
    f = 15;
  };
  hexByte = s: (hexDigits.${lib.toLower (builtins.substring 0 1 s)} * 16) + hexDigits.${lib.toLower (builtins.substring 1 1 s)};
  rgb =
    hex:
    let
      h = lib.removePrefix "#" hex;
    in
    "${toString (hexByte (builtins.substring 0 2 h))},${toString (hexByte (builtins.substring 2 2 h))},${toString (hexByte (builtins.substring 4 2 h))}";

  kwriteconfig6 = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";
in
{
  # Papirus for Dolphin/KDE's file & folder icons -- the same icon theme
  # Nautilus already gets implicitly under GTK. `color` bakes the folder
  # tint in at *build* time: nixpkgs' papirus-icon-theme derivation runs
  # `papirus-folders -C ${color}` itself, on its own writable build
  # directory, before the result becomes an immutable /nix/store path
  # (see pkgs/by-name/pa/papirus-icon-theme/package.nix). Running
  # papirus-folders at runtime/activation against the already-installed
  # package doesn't work under Nix at all -- it rewrites SVGs in place
  # inside the theme directory, which is read-only in the store; it was
  # tried first and failed both on a missing `awk` on the activation
  # script's PATH *and*, after fixing that, on trying to sudo its way
  # around the read-only store once it noticed the theme dir wasn't
  # writable.
  #
  # "blue" is the closest built-in preset to theme.blue (#61afef) --
  # papirus-folders only supports a fixed named palette, not arbitrary
  # hex (confirmed by reading its source), so this compares the shipped
  # preset SVGs' own hex fills against our real blue rather than guessing:
  # blue=#5294e2 was closest, well ahead of nordic/bluegrey.
  home.packages = [
    (pkgs.papirus-icon-theme.override { color = "blue"; })
  ];

  # A native KDE/Qt color scheme (~/.local/share/color-schemes/), built
  # from the same real palette (home/theme/onedark.nix) as every other
  # themed surface in this config. Deliberately NOT the qt5ct/qt6ct
  # platform-theme route home/theme.nix used to take -- that broke Plasma
  # outright (KWin/plasmashell couldn't resolve the QQC2 style once
  # QT_QPA_PLATFORMTHEME was overridden; see home/theme.nix's comment). A
  # .colorscheme file is a different, much narrower mechanism: it only
  # supplies a named color palette for Breeze's own style engine to read,
  # nothing about platform theme/style resolution changes.
  xdg.dataFile."color-schemes/CoelOSOneDark.colorscheme".text = ''
    [ColorEffects:Disabled]
    Color=${rgb theme.comment}
    ColorAmount=0
    ColorEffect=0
    ContrastAmount=0.65
    ContrastEffect=1
    IntensityAmount=0.1
    IntensityEffect=2

    [ColorEffects:Inactive]
    ChangeSelectionColor=true
    Color=${rgb theme.comment}
    ColorAmount=0.025
    ColorEffect=2
    ContrastAmount=0.1
    ContrastEffect=2
    Enable=false
    IntensityAmount=0
    IntensityEffect=0

    [Colors:Button]
    BackgroundAlternate=${rgb theme.surface}
    BackgroundNormal=${rgb theme.surface}
    DecorationFocus=${rgb theme.blue}
    DecorationHover=${rgb theme.blue}
    ForegroundActive=${rgb theme.blue}
    ForegroundInactive=${rgb theme.comment}
    ForegroundLink=${rgb theme.blue}
    ForegroundNegative=${rgb theme.error}
    ForegroundNeutral=${rgb theme.yellow}
    ForegroundNormal=${rgb theme.fg}
    ForegroundPositive=${rgb theme.green}
    ForegroundVisited=${rgb theme.purple}

    [Colors:Selection]
    BackgroundAlternate=${rgb theme.blue}
    BackgroundNormal=${rgb theme.blue}
    DecorationFocus=${rgb theme.blue}
    DecorationHover=${rgb theme.blue}
    ForegroundActive=${rgb theme.bg}
    ForegroundInactive=${rgb theme.bg}
    ForegroundLink=${rgb theme.bg}
    ForegroundNegative=${rgb theme.error}
    ForegroundNeutral=${rgb theme.yellow}
    ForegroundNormal=${rgb theme.bg}
    ForegroundPositive=${rgb theme.green}
    ForegroundVisited=${rgb theme.purple}

    [Colors:Tooltip]
    BackgroundAlternate=${rgb theme.surface}
    BackgroundNormal=${rgb theme.surface}
    DecorationFocus=${rgb theme.blue}
    DecorationHover=${rgb theme.blue}
    ForegroundActive=${rgb theme.blue}
    ForegroundInactive=${rgb theme.comment}
    ForegroundLink=${rgb theme.blue}
    ForegroundNegative=${rgb theme.error}
    ForegroundNeutral=${rgb theme.yellow}
    ForegroundNormal=${rgb theme.fg}
    ForegroundPositive=${rgb theme.green}
    ForegroundVisited=${rgb theme.purple}

    [Colors:View]
    BackgroundAlternate=${rgb theme.surface}
    BackgroundNormal=${rgb theme.bg}
    DecorationFocus=${rgb theme.blue}
    DecorationHover=${rgb theme.blue}
    ForegroundActive=${rgb theme.blue}
    ForegroundInactive=${rgb theme.comment}
    ForegroundLink=${rgb theme.blue}
    ForegroundNegative=${rgb theme.error}
    ForegroundNeutral=${rgb theme.yellow}
    ForegroundNormal=${rgb theme.fg}
    ForegroundPositive=${rgb theme.green}
    ForegroundVisited=${rgb theme.purple}

    [Colors:Window]
    BackgroundAlternate=${rgb theme.surface}
    BackgroundNormal=${rgb theme.bg}
    DecorationFocus=${rgb theme.blue}
    DecorationHover=${rgb theme.blue}
    ForegroundActive=${rgb theme.blue}
    ForegroundInactive=${rgb theme.comment}
    ForegroundLink=${rgb theme.blue}
    ForegroundNegative=${rgb theme.error}
    ForegroundNeutral=${rgb theme.yellow}
    ForegroundNormal=${rgb theme.fg}
    ForegroundPositive=${rgb theme.green}
    ForegroundVisited=${rgb theme.purple}

    [General]
    ColorScheme=CoelOSOneDark
    Name=CoelOS One Dark
    shadeSortColumn=true

    [KDE]
    contrast=4

    [WM]
    activeBackground=${rgb theme.bg}
    activeBlend=${rgb theme.blue}
    activeForeground=${rgb theme.fg}
    inactiveBackground=${rgb theme.bg}
    inactiveBlend=${rgb theme.comment}
    inactiveForeground=${rgb theme.comment}
  '';

  # Applied via kwriteconfig6 (patches one key at a time), not by
  # symlinking kdeglobals/plasmarc wholesale -- Plasma owns and rewrites
  # these live as the user changes things in System Settings, so a full
  # xdg.configFile symlink there would fight it on every login. Same
  # pattern already used for kglobalshortcutsrc in home/kde-shortcuts.nix.
  #
  # kdeglobals' ColorScheme/Icons cover plain Qt Widgets apps (Dolphin,
  # System Settings, ...), which read kdeglobals directly -- that's why
  # Dolphin already looked right without the line below. They do *not*
  # cover the Plasma shell's own chrome (panels, system tray, widgets,
  # task manager): that reads a separate "Plasma Desktop Theme" setting
  # in plasmarc, which LookAndFeelPackage=org.kde.breezedark.desktop
  # (still active -- only its ColorScheme/Icons pieces are overridden
  # above, not the bundle selection itself) had left on a *fixed*-dark
  # theme rather than one that follows the active color scheme. Plasma's
  # bundled "default" theme (KPlugin.Id "default", user-facing name
  # "Breeze" -- not "breeze-dark"/"breeze-light", both of which hardcode
  # their own colors) is the adaptive one: confirmed by decompressing its
  # panel-background.svgz and finding the literal `current-color-scheme`
  # token Plasma's SVG renderer looks for to recolor an element from
  # whatever color scheme is active, i.e. CoelOSOneDark above.
  home.activation.coelKdeTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${kwriteconfig6} --file kdeglobals --group General --key ColorScheme CoelOSOneDark
    $DRY_RUN_CMD ${kwriteconfig6} --file kdeglobals --group Icons --key Theme Papirus
    $DRY_RUN_CMD ${kwriteconfig6} --file plasmarc --group Theme --key name default
  '';
}

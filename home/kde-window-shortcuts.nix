{ config, pkgs, lib, ... }:

let
  # A from-scratch KWin script never got picked up by KWin despite correct
  # logic and metadata, but installing this repo through Plasma's own
  # "Install from File" GUI worked immediately -- using the upstream
  # package directly rather than chasing the missing KPackage step.
  winMaxMin = pkgs.fetchFromGitHub {
    owner = "gcrtnst";
    repo = "kwin-win-max-min";
    rev = "v0.1.0";
    hash = "sha256-PR34FDmGwx9Scha1CyhqJJr9bRvohLU8FfG2hkJQr7I=";
  };
in
{
  # SUPER+Up / SUPER+Down window snapping in KDE Plasma, Windows-style
  # (Hyprland has its own binding in home/hyprland.nix; this doesn't touch
  # that). Uses github.com/gcrtnst/kwin-win-max-min directly.
  #
  # The native "Window Maximize" action defaults to Meta+Up too, so it has
  # to be explicitly cleared here -- otherwise it and the script's own
  # Meta+Up registration would both be trying to claim the same shortcut.
  home.activation.clearNativeMaximizeShortcut = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "Window Maximize" "none,none,Maximize Window"
  '';

  # Installed the same way Plasma's "Install from File" does it
  # (kpackagetool6), instead of hand-placing files under
  # ~/.local/share/kwin/scripts -- that path is missing a KPackage/sycoca
  # registration step that kpackagetool6 handles for us.
  home.activation.installWinMaxMin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kpackage}/bin/kpackagetool6 --type KWin/Script --install "${winMaxMin}" \
      || $DRY_RUN_CMD ${pkgs.kdePackages.kpackage}/bin/kpackagetool6 --type KWin/Script --upgrade "${winMaxMin}"
  '';

  home.activation.enableWinMaxMin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwinrc --group Plugins --key kwin-snap-keysEnabled true
  '';

  # The script's registerShortcut() calls pass "Meta+Up"/"Meta+Down" as a
  # suggested default, but the upstream README documents these as
  # non-default -- they aren't actually bound until assigned in System
  # Settings, so this does that assignment declaratively instead. Group is
  # [kwin], keyed by the internal action name passed as registerShortcut's
  # first argument. The middle field (the "default") must stay "none" --
  # writing a non-none value there makes kglobalaccel disregard the whole
  # entry instead of overriding the active binding.
  home.activation.bindWinMaxMinShortcuts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "WindowsLikeMaximize" "Meta+Up,none,Windows-Like Maximize"
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "WindowsLikeMinimize" "Meta+Down,none,Windows-Like Minimize"
  '';
}

{ config, pkgs, lib, ... }:

let
  # The real thing, not our own reproduction: our from-scratch KWin script
  # (twice) never actually got picked up by KWin even with correct logic
  # and correct metadata fields, but installing this exact repo through
  # Plasma's own "Install from File" GUI worked immediately. Rather than
  # keep guessing at what KPackage step we were missing, install this
  # upstream package directly.
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

  # Installed the same way Plasma's own "Install from File" does it
  # (kpackagetool6), instead of hand-placing files under
  # ~/.local/share/kwin/scripts -- that's what we were doing before across
  # two from-scratch attempts, and KWin never picked either one up despite
  # correct logic and correct metadata, so something about that path is
  # missing a step (likely a KPackage/sycoca registration) that
  # kpackagetool6 handles for us.
  home.activation.installWinMaxMin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kpackage}/bin/kpackagetool6 --type KWin/Script --install "${winMaxMin}" \
      || $DRY_RUN_CMD ${pkgs.kdePackages.kpackage}/bin/kpackagetool6 --type KWin/Script --upgrade "${winMaxMin}"
  '';

  home.activation.enableWinMaxMin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwinrc --group Plugins --key kwin-snap-keysEnabled true
  '';

  # The script's own registerShortcut() calls pass "Meta+Up"/"Meta+Down" as
  # a suggested default, but the upstream README documents these as
  # non-default -- they don't actually get bound to anything until you
  # assign them yourself in System Settings. Doing that assignment here
  # instead. Confirmed the exact group by binding these manually once and
  # reading it back: [kwin], keyed by the internal action name passed as
  # registerShortcut's first argument. The middle field (the "default") has
  # to stay "none" -- that's what a real manual bind produces (the script
  # itself is the source of truth for its own default, which is "none" per
  # the README), and writing a non-none value there caused kglobalaccel to
  # disregard the whole entry rather than just override the active binding.
  home.activation.bindWinMaxMinShortcuts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "WindowsLikeMaximize" "Meta+Up,none,Windows-Like Maximize"
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "WindowsLikeMinimize" "Meta+Down,none,Windows-Like Minimize"
  '';
}

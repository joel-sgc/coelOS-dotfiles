{
  config,
  pkgs,
  lib,
  ...
}:

let
  kwriteconfig6 = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";

  desktopNums = lib.genList (i: i + 1) 9 ++ [ 10 ];
  keyFor = n: if n == 10 then "0" else toString n;

  # The middle field is the "default", not a second copy of the active
  # value -- duplicating it there is exactly what silently broke the KWin
  # script shortcuts earlier this session (kglobalaccel disregarded the
  # whole entry rather than just override the active binding). "none" here
  # since none of these actions have a real compiled-in default anyway.
  switchDesktopBinds = lib.concatMapStrings (n: ''
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group kwin --key "Switch to Desktop ${toString n}" "Meta+${keyFor n},none,Switch to Desktop ${toString n}"
  '') desktopNums;

  windowToDesktopBinds = lib.concatMapStrings (n: ''
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group kwin --key "Window to Desktop ${toString n}" "Meta+Shift+${keyFor n},none,Window to Desktop ${toString n}"
  '') desktopNums;

  clearTaskManagerBinds = lib.concatMapStrings (n: ''
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group plasmashell --key "activate task manager entry ${toString n}" "none,none,Activate Task Manager Entry ${toString n}"
  '') (lib.genList (i: i + 1) 9);
in
{
  # Mirroring a subset of the Hyprland keybinds (home/hyprland.nix) into
  # Plasma, since Plasma's shortcuts got a bit tangled during the
  # maximize/minimize debugging. Same surgical kwriteconfig6 approach as
  # home/kde-window-shortcuts.nix -- only touches the specific keys below,
  # not the whole shortcuts file.

  # Lock screen and close window already have Meta+L / Meta+W as stock KDE
  # defaults, but setting them explicitly rather than assuming they survived
  # the earlier kglobalshortcutsrc churn.
  #
  # "Overview" also claims Meta+W by default (its own default field is
  # literally "Meta+W"), and it was winning the conflict over our Window
  # Close binding, so it has to be explicitly cleared here too -- same
  # category of fix as clearing "Window Maximize" for the maximize script.
  home.activation.kdeLockAndClose = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group ksmserver --key "Lock Session" $'Meta+L\tScreensaver,Meta+L\tScreensaver,Lock Session'
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group kwin --key "Overview" "none,Meta+W,Toggle Overview"
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group kwin --key "Window Close" $'Alt+F4\tMeta+W,Alt+F4,Close Window'
  '';

  # Meta+1..9,0 -> switch to workspace 1..10, Meta+Shift+1..9,0 -> move
  # window to workspace 1..10, matching Hyprland's numbering (key "0" is
  # workspace/desktop 10 on both sides). Meta+1..9 collide with the stock
  # "Activate Task Manager Entry N" default, so those get cleared first.
  home.activation.kdeWorkspaceBinds = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${clearTaskManagerBinds}
    ${switchDesktopBinds}
    ${windowToDesktopBinds}
  '';

  # Klipper's clipboard history is already natively bound to Meta+V by
  # default, matching Hyprland's cliphist bind -- set explicitly rather than
  # assumed, same reasoning as above.
  home.activation.kdeClipboard = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group plasmashell --key "show-on-mouse-pos" "Meta+V,Meta+V,Show Clipboard Items at Mouse Position"
  '';

  # Ghostty and the emoji picker have no native KDE action, so each gets a
  # .desktop entry and a shortcut bound via kglobalaccel's per-app "_launch"
  # mechanism -- the same mechanism (and confirmed real value format) an
  # earlier, now-removed kglobalshortcutsrc snapshot used for Ghostty.
  xdg.desktopEntries.coel-emoji-picker = {
    name = "Emoji Picker";
    exec = "coel-emoji-picker";
    terminal = false;
    noDisplay = true;
    categories = [ "Utility" ];
  };

  # Ghostty's shortcut works off the bat because its .desktop file ships
  # with the package and has long been in KDE's application cache
  # (ksycoca). coel-emoji-picker.desktop is brand new every time it's
  # (re)written here, and kglobalaccel can't resolve a "_launch" target it
  # doesn't know about yet -- same category of "new package, stale cache"
  # issue as the KWin script needing kpackagetool6 instead of a raw file
  # drop. Rebuilding the cache after writing the entry fixes that.
  home.activation.kdeAppLaunchBinds = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group services --group com.mitchellh.ghostty.desktop --key "_launch" "Meta+T"
    $DRY_RUN_CMD ${kwriteconfig6} --file kglobalshortcutsrc --group services --group coel-emoji-picker.desktop --key "_launch" "Meta+."
  '';

  # Print -> screenshot: Spectacle's own default should cover this once the
  # earlier snapshot's explicit disabling of it is gone (that snapshot had
  # CurrentMonitorScreenShot/OpenWithoutScreenshot set to empty). Not adding
  # a surgical override here since Spectacle's actual default action name
  # for the bare Print key isn't confirmed the way the others above are --
  # test this one first and report back rather than layering another guess
  # on top.
}

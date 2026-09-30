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
  # value -- duplicating it there makes kglobalaccel disregard the whole
  # entry instead of overriding the active binding. "none" here since none
  # of these actions have a real compiled-in default anyway.
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
  # Mirrors a subset of the Hyprland keybinds (home/hyprland.nix) into
  # Plasma. Same surgical kwriteconfig6 approach as
  # home/kde-window-shortcuts.nix -- only touches the specific keys below.

  # Lock screen and close window already have Meta+L / Meta+W as stock KDE
  # defaults, set explicitly rather than assumed. "Overview" also claims
  # Meta+W by default and was winning the conflict over Window Close, so it
  # has to be explicitly cleared here too.
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
  # mechanism.
  xdg.desktopEntries.coel-emoji-picker = {
    name = "Emoji Picker";
    exec = "coel-emoji-picker";
    terminal = false;
    noDisplay = true;
    categories = [ "Utility" ];
  };

  # Ghostty's shortcut works off the bat since its .desktop file ships with
  # the package and is already in KDE's application cache (ksycoca).
  # coel-emoji-picker.desktop is rewritten here each time, so kglobalaccel
  # can't resolve its "_launch" target until the cache is rebuilt.
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

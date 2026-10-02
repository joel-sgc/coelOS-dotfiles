{ pkgs, lib, ... }:

let
  icons = import ./icons.nix { inherit lib; };

  # `-d` also deletes old generations of the system profile, which is what
  # actually frees the space; without sudo it would only clean the user's
  # own profiles. Hold-open is inlined as an EXIT trap (fires on failure
  # too) rather than using showDone below, since this doesn't need gum.
  purge = pkgs.writeShellApplication {
    name = "coel-purge";
    text = ''
      hold_open() {
        local status=$?
        echo
        read -n 1 -s -r -p "Press any key to close..."
        exit "$status"
      }
      trap hold_open EXIT

      echo "Purging CoelOS: sudo nix-collect-garbage -d"
      echo
      sudo nix-collect-garbage -d
    '';
  };

  # Launched by home/hyprland.nix's XF86PowerOff bind -- see
  # home/quickshell/power-menu-shell.qml's own comment for why this is a
  # separate, standalone Quickshell process (not part of Panel.qml's
  # already-running shell) and why it points at the live repo path rather
  # than a Nix-store copy. The pgrep guard keys on that same path for the
  # same reason: a second power-key press while the menu's already open
  # should do nothing, not stack a second overlay on top of the first.
  powerMenu = pkgs.writeShellApplication {
    name = "coel-power-menu";
    runtimeInputs = [ pkgs.quickshell pkgs.procps ];
    text = ''
      if pgrep -f "quickshell -p .*power-menu-shell\.qml" >/dev/null; then
        exit 0
      fi
      exec quickshell -p "$HOME/.nixos/home/quickshell/power-menu-shell.qml"
    '';
  };

  rebuild = pkgs.writeShellApplication {
    name = "coel-rebuild";
    runtimeInputs = [ showDone ];
    text = ''
      trap 'coel-show-done --status "$?"' EXIT

      echo "Rebuilding CoelOS: sudo nixos-rebuild switch --flake ~/.nixos#coelos"
      echo
      sudo nixos-rebuild switch --flake "$HOME/.nixos#coelos"
    '';
  };

  update = pkgs.writeShellApplication {
    name = "coel-update";
    runtimeInputs = [ showDone ];
    text = ''
      trap 'coel-show-done --status "$?"' EXIT

      echo "Updating CoelOS: sudo nixos-rebuild switch --flake ~/.nixos#coelos --upgrade"
      echo
      sudo nixos-rebuild switch --flake "$HOME/.nixos#coelos" --upgrade
    '';
  };

  # --- Screenshot / screen recording -------------------------------------
  screenshot = pkgs.writeShellApplication {
    name = "coel-screenshot";
    runtimeInputs = with pkgs; [
      grim
      slurp
      wayfreeze
      satty
      jq
      hyprland
      wl-clipboard
      libnotify
    ];
    text = builtins.readFile ../scripts/coel-screenshot.sh;
  };

  screenrecord = pkgs.writeShellApplication {
    name = "coel-screenrecord";
    runtimeInputs = with pkgs; [
      gpu-screen-recorder
      v4l-utils
      ffmpeg
      hyprland
      jq
      libnotify
      procps
    ];
    text = builtins.readFile ../scripts/coel-screenrecord.sh;
  };

  # --- Fingerprint helpers ------------------------------------------------
  # Keeps a one-shot script's terminal window open until a key is pressed, so
  # output stays scrollable. Scripts built with writeShellApplication
  # (`set -euo pipefail`) would otherwise exit and close ghostty with the
  # error gone before this ever ran, so scripts install it as an EXIT trap
  # instead of calling it at the bottom, which fires on failure too:
  #
  #   trap 'coel-show-done --status "$?"' EXIT
  #
  # `--status N` picks the message: "Done!" for 0, a red failure line
  # otherwise. An optional TITLE can still be passed as the first argument.
  showDone = pkgs.writeShellApplication {
    name = "coel-show-done";
    runtimeInputs = [ pkgs.gum ];
    text = ''
      status=0
      if [ "''${1:-}" = "--status" ]; then
        status="''${2:-0}"
        shift 2
      fi

      # Ctrl+C, or the window itself closing (SIGHUP/SIGTERM): nobody is
      # left to read anything.
      case "$status" in
        129 | 130 | 143) exit "$status" ;;
      esac

      if [ "$status" -ne 0 ]; then
        printf '\n\033[1;31mFailed (exit %s) -- scroll up to see what went wrong.\033[0m\n' "$status"
        TITLE="''${1:-Press any key to close...}"
      else
        TITLE="''${1:-Done! Press any key to close...}"
      fi

      echo
      gum spin --spinner "globe" --title "$TITLE" -- bash -c 'read -n 1 -s'
      exit "$status"
    '';
  };

  fingerprintEnroll = pkgs.writeShellApplication {
    name = "coel-fingerprint-enroll";
    runtimeInputs = [
      pkgs.fprintd
      showDone
    ];
    text = ''
      trap 'coel-show-done --status "$?"' EXIT

      sudo pkill fprintd || true
      sudo fprintd-enroll "$USER"
    '';
  };

  fingerprintDelete = pkgs.writeShellApplication {
    name = "coel-fingerprint-delete";
    runtimeInputs = [ showDone ];
    text = ''
      trap 'coel-show-done --status "$?"' EXIT

      sudo -v
      sleep 0.2
      sudo fprintd-delete "$USER"
    '';
  };

  # Enroll and delete live together in one menu (unlike the split
  # Settings/Uninstall menus this was ported from) so fingerprintDelete has
  # somewhere to be reached from.
  fingerprintMenu = pkgs.writeShellScriptBin "coel-fingerprint-menu" ''
    #!/usr/bin/env bash
    choice=$(printf \
    "${icons.enroll}  Enroll\n\
    ${icons.delete}  Delete\n" | rofi -dmenu -i -p "Fingerprint" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    case "$choice" in
    	*Enroll*) exec ghostty --class=com.joelsgc.floating -e coel-fingerprint-enroll ;;
    	*Delete*) exec ghostty --class=com.joelsgc.floating -e coel-fingerprint-delete ;;
    esac

    if [ "$exit_code" -ne 0 ]; then
        exec coel-settings-menu
    fi
  '';
in
{
  home.packages = [
    purge
    powerMenu
    rebuild
    update
    screenshot
    pkgs.hyprpicker
    screenrecord
    showDone
    fingerprintEnroll
    fingerprintDelete
    fingerprintMenu
  ];
}

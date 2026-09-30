{ pkgs, lib, ... }:

let
  # Counterpart to the old coel-rebuild: same shape (echo the command, run it
  # under sudo, hold the window open afterwards whether it succeeded or not),
  # but runs nix-collect-garbage instead. `-d` also deletes old generations
  # of the system profile, which is what actually frees the space; without
  # sudo it would only clean the user's own profiles.
  #
  # coel-show-done went away with home/rofi.nix, so the hold-open is inlined
  # here as an EXIT trap (fires on failure too, unlike a line at the bottom).
  icons = import ./icons.nix { inherit lib; };

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
  # Ported from bin/screenshot.sh and bin/screenrecord.sh — these had no
  # Arch/Omarchy-package-manager dependencies at all, just Wayland tooling,
  # so they came over unmodified apart from PATH resolution.
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
      waybar
      procps
    ];
    text = builtins.readFile ../scripts/coel-screenrecord.sh;
  };

  # --- Fingerprint helpers ------------------------------------------------
  # Keeps a one-shot script's terminal window open until a key is pressed, so
  # output stays scrollable. Ported from the old dotfiles' bin/show-done.sh,
  # which worked because those scripts had no `set -e`: a failing command
  # fell through to this wait instead of ending the script. Ours are built
  # with writeShellApplication (`set -euo pipefail`), so a failure would exit
  # before ever reaching it and ghostty would close with the error gone.
  # Scripts that want it install it as an EXIT trap instead of calling it
  # at the bottom, which fires on failure too:
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

      # Ctrl+C, or the window itself being closed (SIGHUP/SIGTERM): nobody
      # is left to read anything, and the old scripts closed on Ctrl+C too.
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

  # Ported from uninstall.sh's Fingerprint entry (delete) + settings.sh's
  # Fingerprint entry (enroll) — the original split enroll/delete across two
  # different top-level menus (Settings vs. Uninstall); since Uninstall is
  # now a TODO stub (see mainMenu), both live together here instead so
  # fingerprintDelete still has somewhere to be reached from.
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

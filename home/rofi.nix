{ config, pkgs, lib, ... }:

let
  # --- Menu scripts -----------------------------------------------------
  # Ported from the old Arch/Omarchy dotfiles' configs/rofi/*.sh. Every menu
  # entry from the originals is present here — anything without a real Nix
  # equivalent yet shows a TODO notification (via coel-todo) instead of being
  # silently dropped. Styling is still deferred on purpose (unstyled rofi/
  # waybar, per the "get it working first" priority) — that hasn't changed,
  # only completeness has.
  #
  # Other adaptations:
  #   - alacritty -> ghostty (our terminal)
  #   - absolute ~/.coelOS-dotfiles paths -> bare command names (these are
  #     all on PATH via home.packages, same as each other)
  #   - fixed: `-p` was missing its prompt-text argument in every menu
  #     script in the original (e.g. `-p -lines 10 ... -i "Power"` — the
  #     trailing quoted string was never actually reaching -p); now `-p
  #     "Power"` etc. directly, `-i` kept as rofi's real case-insensitive flag
  #   - fixed: power-profiles.sh captured `$?` *after* the `powerprofilesctl
  #     set` call instead of right after the rofi prompt, so the
  #     cancel-reopens-menu behavior was checking the wrong command's exit
  #     code. Moved it back to directly after the prompt.
  #
  # The menu scripts below (power/actions/settings/power-profiles/
  # fingerprint/config) keep the original's un-guarded `choice=$(rofi ...)`
  # followed by a bare `exit_code=$?` check to decide whether rofi was
  # cancelled. That relies on the script *not* aborting when rofi exits
  # non-zero, so these are plain writeShellScriptBin (no `set -e`) rather
  # than writeShellApplication, on purpose.

  todo = pkgs.writeShellApplication {
    name = "coel-todo";
    runtimeInputs = [ pkgs.libnotify ];
    text = ''
      notify-send -a "CoelOS" -u normal "TODO" "''${1:-Not wired up yet.}"
    '';
  };

  mainMenu = pkgs.writeShellApplication {
    name = "coel-main-menu";
    runtimeInputs = [ pkgs.rofi ];
    text = ''
      choice=$(printf \
      " 󰀻  Programs\n\
       Actions\n\
         Settings\n\
       󱧘  Install\n\
       󱧙  Uninstall\n\
         Update\n\
         About\n\
       System\n" | rofi -dmenu -i -p "Main Menu" -no-fixed-num-lines)

      case "$choice" in
      	*Programs*) rofi -show drun -theme-str 'listview { lines: 10; }' ;;
      	*Actions*) exec coel-actions-menu ;;
      	*Settings*) exec coel-settings-menu ;;
      	*Install*) exec coel-todo "Nix has no imperative package installer menu — add the package to home.nix or configuration.nix and rebuild instead." ;;
      	*Uninstall*) exec coel-todo "Nix has no imperative package uninstaller menu — remove the package from home.nix or configuration.nix and rebuild instead." ;;
      	*Update*) exec ghostty -e coel-update ;;
      	*About*) exec ghostty -e bash -c "fastfetch; read -n1 -r" ;;
      	*System*) exec coel-power-menu ;;
      esac
    '';
  };

  # `Update` in the old menu ran a pacman/yay/flatpak wrapper script. The
  # direct Nix equivalent is a flake rebuild — same command as ~/reload-nix.sh.
  update = pkgs.writeShellApplication {
    name = "coel-update";
    text = ''
      echo "Rebuilding CoelOS: sudo nixos-rebuild switch --flake ~/.nixos#coelos"
      echo
      sudo nixos-rebuild switch --flake "$HOME/.nixos#coelos"
      echo
      read -n 1 -s -r -p "Done. Press any key to close..."
      echo
    '';
  };

  powerMenu = pkgs.writeShellScriptBin "coel-power-menu" ''
    #!/usr/bin/env bash
    choice=$(printf \
    "   Lock\n\
     Suspend\n\
       Restart\n\
     Shutdown\n" | rofi -dmenu -i -p "Power" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    case "$choice" in
    	*Lock*) hyprlock ;;
    	*Suspend*) systemctl suspend ;;
    	*Restart*) systemctl reboot ;;
    	*Shutdown*) systemctl poweroff ;;
    esac

    if [ "$exit_code" -ne 0 ]; then
        exec coel-main-menu
    fi
  '';

  actionsMenu = pkgs.writeShellScriptBin "coel-actions-menu" ''
    #!/usr/bin/env bash
    choice=$(printf \
    " 󰄀  Screenshot\n\
     Screen Record\n\
     Color\n" | rofi -dmenu -i -p "Actions" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    case "$choice" in
    	*Screenshot*) exec coel-screenshot ;;
    	*Record*) exec coel-screenrecord ;;
    	*Color*) exec bash -c "sleep 0.15 && hyprpicker -a" ;;
    esac

    if [ "$exit_code" -ne 0 ]; then
        exec coel-main-menu
    fi
  '';

  settingsMenu = pkgs.writeShellScriptBin "coel-settings-menu" ''
    #!/usr/bin/env bash
    choice=$(printf \
    "   Audio\n\
     󰖩  WiFi\n\
     󰂯  Bluetooth\n\
     󱐋  Power Profiles\n\
     󰍹  Monitors\n\
       Keybindings\n\
     󰍽  Input\n\
     󰈷  Fingerprint\n\
       Config\n" | rofi -dmenu -i -p "Settings" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    case "$choice" in
    	*Audio*) exec ghostty -e pulsemixer ;;
    	*WiFi*) exec coel-todo "WiFi (netpala) isn't adapted to NixOS yet." ;;
    	*Bluetooth*) exec coel-todo "Bluetooth (bluepala) isn't adapted to NixOS yet." ;;
    	*Power\ Profiles*) exec coel-power-profiles-menu ;;
    	*Monitors*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
    	*Keybindings*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
    	*Input*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
    	*Fingerprint*) exec coel-fingerprint-menu ;;
    	*Config*) exec coel-config-menu ;;
    esac

    if [ "$exit_code" -ne 0 ]; then
        exec coel-main-menu
    fi
  '';

  # Ported from config.sh. Monitors/Keybindings/Input/Autostart/Window Rules
  # all used to be separate files; ours are unified into home/hyprland.nix
  # (hyprlock/hypridle settings live in home/hypridle.nix), so several
  # entries below point at the same file — that's a real difference from the
  # old per-concern file split, not a mistake.
  configMenu = pkgs.writeShellScriptBin "coel-config-menu" ''
    #!/usr/bin/env bash
    choice=$(printf \
    "   Hyprland\n\
       Hyprlock\n\
       Hypridle\n\
     󱓞  Autostart\n\
     󱂬  Window Rules\n\
     󰏘  Look & Feel\n\
     󰌧  Waybar\n" | rofi -dmenu -i -p "Config" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    case "$choice" in
    	*Hyprland*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
    	*Hyprlock*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hypridle.nix" ;;
    	*Hypridle*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hypridle.nix" ;;
    	*Autostart*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
    	*Window\ Rules*) exec ghostty -e "$EDITOR" "$HOME/.nixos/home/hyprland.nix" ;;
    	*Look*) exec coel-todo "Look & Feel isn't broken out into its own theme file yet — styling is still deferred." ;;
    	*Waybar*) exec coel-todo "Waybar isn't configured/styled yet." ;;
    esac

    if [ "$exit_code" -ne 0 ]; then
        exec coel-settings-menu
    fi
  '';

  powerProfilesMenu = pkgs.writeShellScriptBin "coel-power-profiles-menu" ''
    #!/usr/bin/env bash
    profiles=$(powerprofilesctl list | awk '/:$/ {gsub("\\*",""); gsub(":",""); print $1}')

    chosen=$(echo "$profiles" | rofi -dmenu -i -p "Power Profiles" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    if [ -n "$chosen" ]; then
        powerprofilesctl set "$chosen"
    fi

    if [ "$exit_code" -ne 0 ]; then
        exec coel-settings-menu
    fi
  '';

  emojiPicker = pkgs.writeShellApplication {
    name = "coel-emoji-picker";
    runtimeInputs = [ pkgs.rofi ];
    text = ''
      rofi -modi emoji -show emoji -theme-str "window {width: 768px;}" -lines 10 -no-fixed-num-lines
    '';
  };

  # --- Screenshot / screen recording -------------------------------------
  # Ported from bin/screenshot.sh and bin/screenrecord.sh — these had no
  # Arch/Omarchy-package-manager dependencies at all, just Wayland tooling,
  # so they came over unmodified apart from PATH resolution.
  screenshot = pkgs.writeShellApplication {
    name = "coel-screenshot";
    runtimeInputs = with pkgs; [ grim slurp wayfreeze satty jq hyprland wl-clipboard libnotify ];
    text = ''
      OUTPUT_DIR="$HOME/Pictures"

      if [[ ! -d "$OUTPUT_DIR" ]]; then
        notify-send "Screenshot directory does not exist: $OUTPUT_DIR" -u critical -t 3000
        exit 1
      fi

      pkill slurp && exit 0

      MODE="''${1:-smart}"
      PROCESSING="''${2:-slurp}"

      get_rectangles() {
        local active_workspace
        active_workspace=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .activeWorkspace.id')
        hyprctl monitors -j | jq -r --arg ws "$active_workspace" '.[] | select(.activeWorkspace.id == ($ws | tonumber)) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"'
        hyprctl clients -j | jq -r --arg ws "$active_workspace" '.[] | select(.workspace.id == ($ws | tonumber)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
      }

      sleep 0.05

      case "$MODE" in
        region)
          wayfreeze & PID=$!
          sleep .1
          SELECTION=$(slurp 2>/dev/null)
          kill "$PID" 2>/dev/null
          ;;
        windows)
          wayfreeze & PID=$!
          sleep .1
          SELECTION=$(get_rectangles | slurp -r 2>/dev/null)
          kill "$PID" 2>/dev/null
          ;;
        fullscreen)
          SELECTION=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | "\(.x),\(.y) \((.width / .scale) | floor)x\((.height / .scale) | floor)"')
          ;;
        smart | *)
          RECTS=$(get_rectangles)
          wayfreeze & PID=$!
          sleep .1
          SELECTION=$(echo "$RECTS" | slurp 2>/dev/null)
          kill "$PID" 2>/dev/null

          if [[ "$SELECTION" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
            if (( BASH_REMATCH[3] * BASH_REMATCH[4] < 20 )); then
              click_x="''${BASH_REMATCH[1]}"
              click_y="''${BASH_REMATCH[2]}"

              while IFS= read -r rect; do
                if [[ "$rect" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+) ]]; then
                  rect_x="''${BASH_REMATCH[1]}"
                  rect_y="''${BASH_REMATCH[2]}"
                  rect_width="''${BASH_REMATCH[3]}"
                  rect_height="''${BASH_REMATCH[4]}"

                  if (( click_x >= rect_x && click_x < rect_x+rect_width && click_y >= rect_y && click_y < rect_y+rect_height )); then
                    SELECTION="$rect_x,$rect_y ''${rect_width}x''${rect_height}"
                    break
                  fi
                fi
              done <<< "$RECTS"
            fi
          fi
          ;;
      esac

      [ -z "$SELECTION" ] && exit 0

      if [[ $PROCESSING == "slurp" ]]; then
        grim -g "$SELECTION" - |
          satty --filename - \
            --output-filename "$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png" \
            --early-exit \
            --actions-on-enter save-to-clipboard \
            --save-after-copy \
            --copy-command 'wl-copy'
      else
        grim -g "$SELECTION" - | wl-copy
      fi
    '';
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
    text = ''
      OUTPUT_DIR="''${OMARCHY_SCREENRECORD_DIR:-''${XDG_VIDEOS_DIR:-$HOME/Videos}}"

      if [[ ! -d "$OUTPUT_DIR" ]]; then
        notify-send "Screen recording directory does not exist: $OUTPUT_DIR" -u critical -t 3000
        exit 1
      fi

      DESKTOP_AUDIO="false"
      MICROPHONE_AUDIO="false"
      WEBCAM="false"
      WEBCAM_DEVICE=""
      STOP_RECORDING="false"

      for arg in "$@"; do
        case "$arg" in
          --with-desktop-audio) DESKTOP_AUDIO="true" ;;
          --with-microphone-audio) MICROPHONE_AUDIO="true" ;;
          --with-webcam) WEBCAM="true" ;;
          --webcam-device=*) WEBCAM_DEVICE="''${arg#*=}" ;;
          --stop-recording) STOP_RECORDING="true" ;;
        esac
      done

      cleanup_webcam() {
        pkill -f "WebcamOverlay" 2>/dev/null || true
      }

      start_webcam_overlay() {
        cleanup_webcam

        if [[ -z "$WEBCAM_DEVICE" ]]; then
          WEBCAM_DEVICE=$(v4l2-ctl --list-devices 2>/dev/null | grep -m1 "^\s*/dev/video" | tr -d '\t')
          if [[ -z "$WEBCAM_DEVICE" ]]; then
            notify-send "No webcam devices found" -u critical -t 3000
            return 1
          fi
        fi

        local scale
        scale=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .scale')

        local target_width
        target_width=$(awk "BEGIN {printf \"%.0f\", 360 * $scale}")

        local preferred_resolutions=("640x360" "1280x720" "1920x1080")
        local video_size_arg=""
        local available_formats
        available_formats=$(v4l2-ctl --list-formats-ext -d "$WEBCAM_DEVICE" 2>/dev/null)

        for resolution in "''${preferred_resolutions[@]}"; do
          if echo "$available_formats" | grep -q "$resolution"; then
            video_size_arg="-video_size $resolution"
            break
          fi
        done

        # shellcheck disable=SC2086
        ffplay -f v4l2 $video_size_arg -framerate 30 "$WEBCAM_DEVICE" \
          -vf "scale=''${target_width}:-1" \
          -window_title "WebcamOverlay" \
          -noborder \
          -fflags nobuffer -flags low_delay \
          -probesize 32 -analyzeduration 0 \
          -loglevel quiet &
        sleep 1
      }

      start_screenrecording() {
        local filename
        filename="$OUTPUT_DIR/screenrecording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
        local audio_devices=""
        local audio_args=""

        [[ "$DESKTOP_AUDIO" == "true" ]] && audio_devices+="default_output"

        if [[ "$MICROPHONE_AUDIO" == "true" ]]; then
          [[ -n "$audio_devices" ]] && audio_devices+="|"
          audio_devices+="default_input"
        fi

        [[ -n "$audio_devices" ]] && audio_args+="-a $audio_devices"

        # shellcheck disable=SC2086
        gpu-screen-recorder -w portal -f 60 -fallback-cpu-encoding yes -o "$filename" $audio_args -ac aac &
        toggle_screenrecording_indicator
      }

      stop_screenrecording() {
        pkill -SIGINT -f "^gpu-screen-recorder" || true

        local count=0
        while pgrep -f "^gpu-screen-recorder" >/dev/null && [ $count -lt 50 ]; do
          sleep 0.1
          count=$((count + 1))
        done

        if pgrep -f "^gpu-screen-recorder" >/dev/null; then
          pkill -9 -f "^gpu-screen-recorder"
          cleanup_webcam
          notify-send "Screen recording error" "Recording process had to be force-killed. Video may be corrupted." -u critical -t 5000
        else
          cleanup_webcam
          notify-send "Screen recording saved to $OUTPUT_DIR" -t 2000
        fi
        toggle_screenrecording_indicator
      }

      toggle_screenrecording_indicator() {
        pkill -RTMIN+8 waybar || true
      }

      screenrecording_active() {
        pgrep -f "^gpu-screen-recorder" >/dev/null || pgrep -f "WebcamOverlay" >/dev/null
      }

      if screenrecording_active; then
        if pgrep -f "WebcamOverlay" >/dev/null && ! pgrep -f "^gpu-screen-recorder" >/dev/null; then
          cleanup_webcam
        else
          stop_screenrecording
        fi
      elif [[ "$STOP_RECORDING" == "false" ]]; then
        [[ "$WEBCAM" == "true" ]] && start_webcam_overlay

        start_screenrecording || cleanup_webcam
      else
        exit 1
      fi
    '';
  };

  # --- Fingerprint helpers ------------------------------------------------
  showDone = pkgs.writeShellApplication {
    name = "coel-show-done";
    runtimeInputs = [ pkgs.gum ];
    text = ''
      TITLE="''${1:-Done! Press any key to close...}"
      echo
      gum spin --spinner "globe" --title "$TITLE" -- bash -c 'read -n 1 -s'
    '';
  };

  fingerprintEnroll = pkgs.writeShellApplication {
    name = "coel-fingerprint-enroll";
    runtimeInputs = [ pkgs.fprintd showDone ];
    text = ''
      sudo pkill fprintd || true
      sudo fprintd-enroll "$USER"
      exec coel-show-done
    '';
  };

  fingerprintDelete = pkgs.writeShellApplication {
    name = "coel-fingerprint-delete";
    runtimeInputs = [ showDone ];
    text = ''
      sudo -v
      sleep 0.2
      sudo rm -rf /var/lib/fprint/*
      exec coel-show-done
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
    "   Enroll\n\
       Delete\n" | rofi -dmenu -i -p "Fingerprint" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    case "$choice" in
    	*Enroll*) exec ghostty -e coel-fingerprint-enroll ;;
    	*Delete*) exec ghostty -e coel-fingerprint-delete ;;
    esac

    if [ "$exit_code" -ne 0 ]; then
        exec coel-settings-menu
    fi
  '';
in
{
  # rofi-emoji needs to be baked into the rofi package itself (rofi loads
  # modi plugins from its own plugin path), so this replaces the plain
  # pkgs.rofi package that used to live in home.nix's home.packages.
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    plugins = [ pkgs.rofi-emoji ];
  };

  home.packages = [
    todo
    mainMenu
    update
    powerMenu
    actionsMenu
    settingsMenu
    configMenu
    powerProfilesMenu
    emojiPicker
    screenshot
    screenrecord
    showDone
    fingerprintEnroll
    fingerprintDelete
    fingerprintMenu
    pkgs.hyprpicker
    pkgs.pulsemixer
    pkgs.fastfetch
  ];
}

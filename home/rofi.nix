{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config.lib.formats.rasi) mkLiteral;

  theme = import ./theme/onedark.nix;

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

  # `--class=com.joelsgc.floating`/`com.joelsgc.info` below tag one-off
  # utility ghostty windows so home/hyprland.nix's windowrules float them
  # instead of tiling -- ported from the old dotfiles' equivalent
  # `alacritty --class com.joelsgc.floating -e ...` convention.

  # Place these 2 in between "Settings" and "Update" when ready
  # 󱧘  Install\n\
  # 󱧙  Uninstall\n\
  mainMenu = pkgs.writeShellApplication {
    name = "coel-main-menu";
    runtimeInputs = [ pkgs.rofi ];
    text = ''
            choice=$(printf \
            "󰀻  Programs\n\
      󱓞  Actions\n\
        Settings\n\
        Rebuild\n\
        Update\n\
        About\n\
      󰤆  System\n" | rofi -dmenu -i -p "Main Menu" -no-fixed-num-lines)

            case "$choice" in
            	*Programs*) rofi -show drun -theme-str 'listview { lines: 10; }' ;;
            	*Actions*) exec coel-actions-menu ;;
            	*Settings*) exec coel-settings-menu ;;
            	*Install*) exec ghostty --class=com.joelsgc.floating -e coel-package-search ;;
            	*Uninstall*) exec coel-todo "Nix has no imperative package uninstaller menu — remove the package from home.nix or configuration.nix and rebuild instead." ;;
            	*Rebuild*) exec ghostty --class=com.joelsgc.floating -e coel-rebuild ;;
            	*Update*) exec ghostty --class=com.joelsgc.floating -e coel-update ;;
            	*About*) exec ghostty --class=com.joelsgc.info -e bash -c "fastfetch; read -n1 -r" ;;
            	*System*) exec coel-power-menu ;;
            esac
    '';
  };

  # `Update` in the old menu ran a pacman/yay/flatpak wrapper script. Split
  # into two here since Nix distinguishes "rebuild from the current
  # flake.lock" from "pull newer flake inputs first, then rebuild": Rebuild
  # is the direct equivalent (same command as ~/reload-nix.sh), Update is
  # the same thing plus `--upgrade` to update flake inputs (nixpkgs, etc.)
  # before building.
  rebuild = pkgs.writeShellApplication {
    name = "coel-rebuild";
    text = ''
      echo "Rebuilding CoelOS: sudo nixos-rebuild switch --flake ~/.nixos#coelos"
      echo
      sudo nixos-rebuild switch --flake "$HOME/.nixos#coelos"
      echo
      read -n 1 -s -r -p "Done. Press any key to close..."
      echo
    '';
  };

  update = pkgs.writeShellApplication {
    name = "coel-update";
    text = ''
      echo "Updating CoelOS: sudo nixos-rebuild switch --flake ~/.nixos#coelos --upgrade"
      echo
      sudo nixos-rebuild switch --flake "$HOME/.nixos#coelos" --upgrade
      echo
      read -n 1 -s -r -p "Done. Press any key to close..."
      echo
    '';
  };

  # Nix has no imperative installer, so this is a *search*, not an install:
  # look up a package and copy the resolved `pkgs.<attr>` path(s) to the
  # clipboard so they can be pasted straight into home.nix's/
  # configuration.nix's package lists.
  #
  # `nix search nixpkgs` (local eval of every one of ~108k package
  # attributes) was tried first and genuinely wasn't good enough: no
  # up-front narrowing meant "tests.*" internal test derivations and other
  # junk cluttered results, and naive substring matching against the whole
  # line meant queries like "ncdu" could match unrelated packages whose
  # *description* happened to mention it. Rebuilt instead on `nix-search`
  # (nixpkgs' `nix-search-cli`), which queries the same relevance-ranked
  # Elasticsearch index behind search.nixos.org -- same backend the
  # official website uses, so junk/false-positive filtering is already
  # solved upstream instead of hand-rolled here.
  #
  # fzf's `--disabled` + `change:reload` is the standard pattern for a live
  # external-search UI: fzf stops doing its own local filtering entirely
  # and just displays whatever coel-package-search-query returns for the
  # current query text ({q}), re-run on every keystroke -- true
  # search-as-you-type against the real API, no local package list at all.
  packageSearchQuery = pkgs.writeShellApplication {
    name = "coel-package-search-query";
    runtimeInputs = [
      pkgs.nix-search-cli
      pkgs.jq
      pkgs.gawk
    ];
    text = ''
      query="''${1:-}"
      if [ -z "$query" ]; then
        exit 0
      fi

      # Channel matches this flake's nixpkgs input (flake.nix: nixos-26.05)
      # as closely as search.nixos.org's indexed channels allow -- attribute
      # names/paths are stable enough across a release line that an exact
      # revision match isn't necessary for this to be useful.
      nix-search --channel=26.05 --search "$query" --json --max-results 60 2>/dev/null | jq -r '
        [.package_attr_name, (.package_pversion // "?"), (.package_description // "no description")]
        | @tsv
      ' | awk -F'\t' '{ printf "%-40s  %-16s  %s\n", $1, $2, $3 }'
    '';
  };

  # Modeled on the old Arch/Omarchy dotfiles' bin/pacman-install.sh and
  # bin/yay-install.sh: an fzf TUI with a live preview pane, multi-select
  # (tab), and pointer/marker colored to match the theme -- run inside a
  # floating ghostty (see home/hyprland.nix's `com.joelsgc.floating`
  # windowrule) rather than a rofi popup. `pointer:green,marker:green` below
  # is fzf's *named* ANSI color, not a literal hex -- it resolves through
  # whatever ghostty theme is active (ANSI 2), so no hardcoded color needs
  # to track theme changes. Proven when this went from Everforest to
  # Dracula with zero changes needed here.
  packageSearch = pkgs.writeShellApplication {
    name = "coel-package-search";
    runtimeInputs = [
      pkgs.fzf
      pkgs.gawk
      pkgs.wl-clipboard
      showDone
      packageSearchQuery
    ];
    text = ''
      selection=$(fzf \
        --disabled \
        --multi \
        --prompt 'Search nixpkgs> ' \
        --bind 'change:reload:sleep 0.15; coel-package-search-query {q}' \
        --preview 'printf "Package: %s\nVersion: %s\n\n%s\n" {1} {2} {3..}' \
        --preview-label='tab: multi-select, alt-p: toggle description, alt-j/k: scroll' \
        --preview-label-pos='bottom' \
        --preview-window 'down:40%:wrap' \
        --bind 'alt-p:toggle-preview' \
        --bind 'alt-j:preview-down,alt-k:preview-up' \
        --color 'pointer:green,marker:green')

      if [ -z "$selection" ]; then
        exit 0
      fi

      copy_text=$(echo "$selection" | awk '{print "pkgs." $1}')
      printf '%s' "$copy_text" | wl-copy

      echo
      echo "Copied to clipboard -- paste into home.nix or configuration.nix and rebuild:"
      echo "$copy_text"
      exec coel-show-done
    '';
  };

  powerMenu = pkgs.writeShellScriptBin "coel-power-menu" ''
        #!/usr/bin/env bash
        choice=$(printf \
        "  Lock\n\
    󰍃  Logout\n\
    󰤄  Suspend\n\
      Restart\n\
    󰤆  Shutdown\n" | rofi -dmenu -i -p "Power" -lines 10 -no-fixed-num-lines)

        exit_code=$?

        case "$choice" in
        	*Lock*) hyprlock ;;
        	*Logout*) hyprctl dispatch exit ;;
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
        "󰄀  Screenshot\n\
      Screen Record\n\
      Color\n" | rofi -dmenu -i -p "Actions" -lines 10 -no-fixed-num-lines)

        exit_code=$?

        case "$choice" in
        	*Screenshot*) exec bash -c "sleep 0.15 && coel-screenshot" ;;
        	*Record*) exec bash -c "sleep 0.15 && coel-screenrecord" ;;
        	*Color*) exec bash -c "sleep 0.15 && hyprpicker -a" ;;
        esac

        if [ "$exit_code" -ne 0 ]; then
            exec coel-main-menu
        fi
  '';

  settingsMenu = pkgs.writeShellScriptBin "coel-settings-menu" ''
        #!/usr/bin/env bash
        choice=$(printf \
        "  Audio\n\
    󰖩  WiFi\n\
    󰂯  Bluetooth\n\
    󱐋  Power Profiles\n\
    󰍹  Monitors\n\
      Keybindings\n\
    󰍽  Input\n\
    󰈷  Fingerprint\n\
      Config\n" | rofi -dmenu -i -p "Settings" -lines 10 -no-fixed-num-lines)

        exit_code=$?

        case "$choice" in
        	*Audio*) exec ghostty --class=com.joelsgc.floating -e pulsemixer ;;
        	*WiFi*) exec ghostty --class=com.joelsgc.floating -e netpala ;;
        	*Bluetooth*) exec ghostty --class=com.joelsgc.floating -e bluepala ;;
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
        "  Hyprland\n\
      Hyprlock\n\
      Hypridle\n\
    󱓞  Autostart\n\
    󱂬  Window Rules\n\
    󰏘  Look & Feel\n\
    󰌧  Waybar" | rofi -dmenu -i -p "Config" -lines 10 -no-fixed-num-lines)

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
    runtimeInputs = [
      pkgs.fprintd
      showDone
    ];
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
      sudo fprintd-delete "$USER"
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
    	*Enroll*) exec ghostty --class=com.joelsgc.floating -e coel-fingerprint-enroll ;;
    	*Delete*) exec ghostty --class=com.joelsgc.floating -e coel-fingerprint-delete ;;
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

    # Ported structurally verbatim from the old Arch/Omarchy dotfiles'
    # theme/rofi.rasi (window/listview/element layout, spacing, the
    # icon-current-entry preview pane, etc.) -- only the color source
    # changed. The original hardcoded `* { urgent: #ff99da; accent:
    # #7acdcd; text: #d4d4d4; base: #262626; }` at the top of the same
    # file; those four vars are now sourced from the static One Dark
    # palette (home/theme/onedark.nix) instead, so @urgent/@accent/
    # @text/@base below resolve the same way they did against the inline
    # block originally.
    #
    # Not ported: an `@media (enabled: env(PREVIEW, false))` block that
    # swapped in a split icon-preview layout. That's Omarchy's own
    # rofi-theme-selector preview tooling reaching into an env var we have
    # no equivalent producer for, and `@media`/`env()` conditionals aren't
    # common enough rofi syntax to risk shipping unverified -- dropped
    # rather than guessed at.
    theme = {
      "*" = {
        # Single font, matching `font` below -- the original dotfiles'
        # theme/rofi.rasi declared `"JetBrainsMonoNL Nerd Font 24, FiraCode
        # Nerd Font Mono 16"` here, which is not a valid Pango font
        # description (only one trailing size is recognized; a second size
        # embedded mid-string gets swallowed into the first family name,
        # e.g. "JetBrainsMonoNL Nerd Font 24" as a literal, nonexistent
        # family). That's almost certainly why icons rendered inconsistently
        # -- font resolution for the first fallback was silently broken.
        # Standardized on FiraCode Nerd Font Mono (matching home/ghostty.nix)
        # instead of JetBrainsMono -- one Nerd Font across the whole desktop.
        font = "FiraCode Nerd Font Mono 20";
        urgent = mkLiteral theme.yellow;
        accent = mkLiteral theme.blue;
        text = mkLiteral theme.fg;
        base = mkLiteral theme.bg;
      };

      window = {
        width = mkLiteral "512px";
        "border-radius" = mkLiteral "8px";
        border = mkLiteral "2px";
        "border-color" = mkLiteral "@accent";
        padding = mkLiteral "48px";
        "background-color" = mkLiteral "@base";
      };

      wrap = {
        expand = false;
        children = [ (mkLiteral "inputbar") ];
      };

      "mainbox, listview, element, element-text, entry, wrap, listview-split, icon-current-entry" = {
        "background-color" = mkLiteral "transparent";
      };

      listview = {
        spacing = mkLiteral "16px";
        padding = mkLiteral "16px 0 0 0";
      };

      "listview-split" = {
        orientation = mkLiteral "horizontal";
        spacing = mkLiteral "24px";
        children = map mkLiteral [
          "listview"
          "icon-current-entry"
        ];
      };

      element = {
        padding = mkLiteral "8px";
      };

      "element-text" = {
        "text-color" = mkLiteral "@accent";
      };

      "element-text selected" = {
        "text-color" = mkLiteral "@urgent";
      };

      "element-icon" = {
        size = mkLiteral "0px";
      };

      "icon-current-entry" = {
        expand = false;
        size = mkLiteral "35%";
      };

      inputbar = {
        padding = mkLiteral "12px";
        children = [ (mkLiteral "entry") ];
        "background-color" = mkLiteral "@base";
      };

      entry = {
        placeholder = "Go...";
        "placeholder-color" = mkLiteral "@text";
        "text-color" = mkLiteral "@text";
      };
    };

    # Ported from the old config.rasi's `configuration { ... }` block,
    # except the size: the original left it unsized here while theme/rofi.rasi
    # set a (broken, see above) JetBrainsMono-based font -- two different
    # fonts for the same UI. Normalized to the single font above so every
    # rofi surface resolves identically.
    font = "FiraCode Nerd Font Mono 20";
    extraConfig = {
      "disable-history" = true;
      "disable-sort" = false;
      matching = "normal";
      "scroll-method" = 1;
    };
  };

  home.packages = [
    todo
    mainMenu
    rebuild
    update
    packageSearchQuery
    packageSearch
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
  ];
}

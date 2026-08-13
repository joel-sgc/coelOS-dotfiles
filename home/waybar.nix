{ pkgs, ... }:

let
  theme = import ./theme/onedark.nix;

  # Ported from the old Arch/Omarchy dotfiles' bin/screenrecording-indicator.sh
  # -- reports current recording state to the custom/screenrecording-indicator
  # module below via waybar's `return-type: json` custom-module protocol.
  # Uses the exact same `pgrep -f "^gpu-screen-recorder"` check coel-screenrecord
  # (home/rofi.nix) itself uses to decide start vs. stop.
  screenrecordingIndicator = pkgs.writeShellApplication {
    name = "coel-screenrecording-indicator";
    runtimeInputs = [ pkgs.procps ];
    text = ''
      if pgrep -f "^gpu-screen-recorder" >/dev/null; then
        echo '{"text": "  ", "tooltip": "Stop recording", "class": "active"}'
      else
        echo '{"text": ""}'
      fi
    '';
  };

  # Home-grown replacement for the old dotfiles' "custom/privacy-dots"
  # module, whose `exec: "privacy-dots"` was some external Arch/AUR tool
  # with no NixOS equivalent. Polled every 3s (matching the original
  # module's own `interval`), same as coel-screenrecording-indicator above.
  #
  # Mic: PipeWire's own object graph (`pw-dump`) is checked directly rather
  # than going through the pulseaudio-compat `pactl` (not installed here) --
  # any node classed "Stream/Input/Audio" that's actually "running" (not
  # just idle/suspended) means something is actively recording.
  #
  # Camera: checked at the device level (`fuser` on /dev/video*) rather than
  # via PipeWire, since not every app that grabs a webcam routes through
  # PipeWire's camera portal -- some open /dev/video* directly. This catches
  # both cases; PipeWire-only camera streams still end up holding the
  # device open too.
  privacyDots = pkgs.writeShellApplication {
    name = "coel-privacy-dots";
    runtimeInputs = [ pkgs.pipewire pkgs.jq pkgs.psmisc ];
    text = ''
      mic_active=false
      if pw-dump 2>/dev/null | jq -e '
        any(.[]?; (.info.props["media.class"]? // "") == "Stream/Input/Audio" and .info.state == "running")
      ' >/dev/null 2>&1; then
        mic_active=true
      fi

      camera_active=false
      shopt -s nullglob
      for dev in /dev/video*; do
        if fuser "$dev" >/dev/null 2>&1; then
          camera_active=true
          break
        fi
      done
      shopt -u nullglob

      text=""
      tooltip_lines=()

      if [ "$mic_active" = true ]; then
        text+=" "
        tooltip_lines+=("Microphone in use")
      fi

      if [ "$camera_active" = true ]; then
        text+=""
        tooltip_lines+=("Camera in use")
      fi

      tooltip=$(printf '%s\n' "''${tooltip_lines[@]-}")
      jq -nc --arg text "$text" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
    '';
  };
in
{
  # Ported structurally from the old Arch/Omarchy dotfiles' configs/waybar.jsonc
  # -- layout/modules/formats unchanged, only command targets adapted:
  #   - alacritty -> ghostty (our terminal)
  #   - absolute ~/.coelOS-dotfiles paths -> our real coel-* commands
  # Bubble/text colors below are the One Dark palette (home/theme/onedark.nix),
  # matching the rest of the desktop -- layout/fonts/borders beyond that are
  # still deferred, a deeper styling pass comes later.
  #
  # "custom/privacy-dots" (modules-center) is our own coel-privacy-dots
  # (defined above) rather than the original's `exec: "privacy-dots"` --
  # that was some external Arch/AUR tool with no NixOS package found.
  #
  # bluetooth's on-click launches bluepala, network's launches netpala --
  # both wired up in configuration.nix (bluepala has no nixosModule so it's
  # a plain systemPackages entry; netpala's is a programs.netpala.enable
  # toggle) -- in a floating terminal, same convention as pulseaudio/cpu
  # below. home/rofi.nix's settingsMenu still has its own separate
  # coel-todo stub for these, untouched here.
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        height = 40;
        margin-left = 16;
        margin-right = 16;
        margin-top = 16;
        spacing = 16;

        modules-left = [
          "custom/launcher"
          "hyprland/workspaces"
        ];
        modules-center = [
          "clock"
          "custom/screenrecording-indicator"
          "custom/privacy-dots"
        ];
        modules-right = [
          "group/tray-expander"
          "bluetooth"
          "network"
          "pulseaudio"
          "cpu"
          "battery"
        ];

        # Original had a hamburger-style glyph here (format = "  "); swapped
        # for the actual Coel.svg logo instead -- waybar custom modules can
        # only render text/Pango markup, not an image, directly from JSON,
        # so the image itself is a `background-image` CSS rule below.
        "custom/launcher" = {
          format = "  ";
          tooltip = false;
          on-click = "coel-main-menu";
        };

        "hyprland/workspaces" = {
          on-click = "activate";
          format = "{icon}";
          format-icons = {
            "1" = "1";
            "2" = "2";
            "3" = "3";
            "4" = "4";
            "5" = "5";
            "6" = "6";
            "7" = "7";
            "8" = "8";
            "9" = "9";
            active = "<span></span>";
          };
          persistent-workspaces = {
            "1" = [ ];
            "2" = [ ];
            "3" = [ ];
            "4" = [ ];
            "5" = [ ];
          };
        };

        clock = {
          timezone = "America/Chicago";
          format = "{:L%A @ %I:%M %p}";
          tooltip-format = "{calendar}";
          calendar = {
            mode = "month";
            format = {
              months = "<span color='${theme.fg}'><b>{}</b></span>\n--------------------";
              days = "<span color='${theme.fg}'><b>{}</b></span>";
              weekdays = "<span color='${theme.yellow}'><b>{}</b></span>";
              today = "<span color='${theme.blue}'><b>{}</b></span>";
            };
          };
        };

        "custom/screenrecording-indicator" = {
          on-click = "coel-screenrecord";
          exec = "coel-screenrecording-indicator";
          signal = 8;
          return-type = "json";
        };

        "custom/privacy-dots" = {
          exec = "coel-privacy-dots";
          return-type = "json";
          interval = 3;
          tooltip = true;
        };

        "group/tray-expander" = {
          orientation = "inherit";
          drawer = {
            transition-duration = 600;
            children-class = "tray-group-item";
          };
          modules = [ "custom/expand-icon" "tray" ];
        };

        "custom/expand-icon" = {
          format = "";
          tooltip = false;
          on-scroll-up = "";
          on-scroll-down = "";
          on-scroll-left = "";
          on-scroll-right = "";
        };

        tray = {
          icon-size = 12;
          spacing = 17;
        };

        bluetooth = {
          # format/format-on were empty strings before -- waybar's bluetooth
          # module falls back to `format` for any state without its own
          # more specific format string, so with both blank the widget was
          # literally invisible (zero-width, no icon) the entire time the
          # radio was on with nothing connected -- the common case. All
          # states now always resolve to a real glyph (verified against
          # nerd-fonts' own glyphnames.json: md-bluetooth/md-bluetooth_off/
          # md-bluetooth_connect), so it shows regardless of radio/adapter
          # state instead of only when a device happens to be connected.
          format = "󰂯";
          format-on = "󰂯";
          format-off = "󰂲";
          format-disabled = "󰂲";
          format-connected = "󰂱";
          format-no-controller = "󰂲";
          tooltip-format = "Devices connected: {num_connections}";
          on-click = "ghostty --class=com.joelsgc.floating -e bluepala";
        };

        network = {
          format-icons = [ "󰤯" "󰤟" "󰤢" "󰤥" "󰤨" ];
          format = "{icon}";
          format-wifi = "{icon}";
          format-ethernet = "󰀂";
          format-disconnected = "󰤮";
          tooltip-format-wifi = "{essid} ({frequency} GHz)\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
          tooltip-format-ethernet = "⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
          tooltip-format-disconnected = "Disconnected";
          interval = 3;
          spacing = 1;
          on-click = "ghostty --class=com.joelsgc.floating -e netpala";
        };

        pulseaudio = {
          format = "{icon}";
          on-click = "ghostty --class=com.joelsgc.floating -e pulsemixer";
          on-click-right = "pamixer -t";
          tooltip-format = "Playing at {volume}%";
          scroll-step = 5;
          format-muted = "";
          format-icons = {
            headphone = "";
            default = [ "" "" "" ];
          };
        };

        cpu = {
          interval = 5;
          format = "󰍛";
          on-click = "ghostty --class=com.joelsgc.floating -e btop";
          on-click-right = "ghostty";
        };

        battery = {
          format = "{icon}  ";
          format-discharging = "{icon}  ";
          format-charging = "{icon}  ";
          format-plugged = "  ";
          format-icons = {
            charging = [ "󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅" ];
            default = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
          };
          format-full = "󰂅";
          tooltip-format-discharging = "{power:>1.0f}W↓ {capacity}%";
          tooltip-format-charging = "{power:>1.0f}W↑ {capacity}%";
          interval = 5;
          on-click = "coel-power-profiles-menu";
          states = {
            warning = 20;
            critical = 10;
          };
        };
      };
    };

    # Beyond the launcher logo, the transparent-bar/floating-bubble layout,
    # and the bubble/calendar colors below, this is intentionally unstyled
    # -- fonts/borders/spacing etc. for individual modules are still
    # deferred to a later, deeper theming pass.
    style = ''
      window#waybar {
        background: transparent;
        border: none;
        box-shadow: none;
      }

      /* "Bubble" look: each real module floats on its own rounded
         background instead of sitting on one continuous opaque bar.
         custom/separator is deliberately left out -- it's just a thin
         divider glyph, not something that reads as its own module. */
      #custom-launcher,
      #workspaces,
      #clock,
      #custom-screenrecording-indicator,
      #custom-privacy-dots,
      #group-tray-expander,
      #bluetooth,
      #network,
      #pulseaudio,
      #cpu,
      #battery {
        /* rgba(), not an 8-digit #RRGGBBAA hex -- GTK's CSS engine doesn't
           support that newer hex-alpha syntax ("Junk at end of value").
           64, 71, 84 is theme.surface (#404754) in decimal. */
        background-color: rgba(64, 71, 84, 0.8);
        border-radius: 16px;
        padding: 4px 12px;
      }

      /* The url() below is a Nix path interpolation, resolved to the
         logo's actual Nix store path at build time -- GTK's CSS url()
         loads that directly, no separate xdg.configFile copy needed. */
      #custom-launcher {
        background-image: url("${./assets/Coel.svg}");
        background-repeat: no-repeat;
        background-position: center;
        background-size: 20px 20px;
        min-width: 40px;
        min-height: 20px;
      }
    '';
  };

  home.packages = [ screenrecordingIndicator privacyDots pkgs.pamixer ];
}

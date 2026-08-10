{ pkgs, ... }:

let
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
in
{
  # Ported structurally from the old Arch/Omarchy dotfiles' configs/waybar.jsonc
  # -- layout/modules/formats unchanged, only command targets adapted:
  #   - alacritty -> ghostty (our terminal)
  #   - absolute ~/.coelOS-dotfiles paths -> our real coel-* commands
  # Not styled on purpose (no `style` set below) -- theming comes later.
  #
  # Not ported: "custom/privacy-dots" (was in modules-center). Its
  # `exec: "privacy-dots"` was some external Arch/AUR tool with no NixOS
  # package found -- dropped rather than left as a broken module reference.
  #
  # Bluetooth/network on-click point at coel-todo, matching the exact
  # "isn't adapted to NixOS yet" stubs already in home/rofi.nix's
  # settingsMenu (bluepala/netpala aren't packaged for NixOS).
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        height = 40;
        margin-left = 32;
        margin-right = 32;
        margin-top = 16;
        spacing = 4;

        modules-left = [
          "custom/launcher"
          "custom/separator"
          "hyprland/workspaces"
        ];
        modules-center = [
          "clock"
          "custom/screenrecording-indicator"
        ];
        modules-right = [
          "group/tray-expander"
          "bluetooth"
          "network"
          "pulseaudio"
          "cpu"
          "battery"
        ];

        "custom/launcher" = {
          format = "  ";
          tooltip = false;
          on-click = "coel-main-menu";
        };

        "custom/separator" = {
          format = "|";
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
            # Colors below are the *old* Arch/Omarchy palette, left
            # untouched on purpose -- not themed yet.
            format = {
              months = "<span color='#d4d4d4'><b>{}</b></span>\n--------------------";
              days = "<span color='#d4d4d4'><b>{}</b></span>";
              weekdays = "<span color='#ff99da'><b>{}</b></span>";
              today = "<span color='#7acdcd'><b>{}</b></span>";
            };
          };
        };

        "custom/screenrecording-indicator" = {
          on-click = "coel-screenrecord";
          exec = "coel-screenrecording-indicator";
          signal = 8;
          return-type = "json";
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
          format = "";
          format-off = "󰂲";
          format-disabled = "󰂲";
          format-connected = "󰂱";
          format-no-controller = "";
          tooltip-format = "Devices connected: {num_connections}";
          on-click = "coel-todo \"Bluetooth (bluepala) isn't adapted to NixOS yet.\"";
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
          on-click = "coel-todo \"WiFi (netpala) isn't adapted to NixOS yet.\"";
        };

        pulseaudio = {
          format = "{icon}";
          on-click = "ghostty --class=com.joelsgc.floating -e pulsemixer";
          on-click-right = "pamixer -t";
          tooltip-format = "Playing at {volume}%";
          scroll-step = 5;
          format-muted = "";
          format-icons = {
            headphone = "";
            default = [ "" "" "" ];
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
  };

  home.packages = [ screenrecordingIndicator pkgs.pamixer ];
}

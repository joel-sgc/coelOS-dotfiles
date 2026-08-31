{ config, pkgs, lib, ... }:

let
  # Nix string literals have no escape for arbitrary byte values, so the
  # ANSI escape byte used by the box-drawing/color-swatch entries below is
  # generated at build time via a trivial derivation instead of being
  # pasted directly into this file as an invisible control character.
  esc = builtins.readFile (
    pkgs.runCommand "fastfetch-esc-byte" { } ''printf '\033' > $out''
  );

  logoPath = "${config.xdg.configHome}/fastfetch/ascii-logo.txt";
in
{
  # Ported from configs/fastfetch.jsonc on the old Arch/Omarchy dotfiles
  # (coelOS-dotfiles, "arch" branch). Layout/keys/colors are unchanged;
  # only the Omarchy-specific `omarchy-*` helper commands had no direct
  # equivalent and were swapped for real NixOS/flake analogues rather than
  # dropped silently:
  #   - omarchy-version            -> nixos-version
  #   - omarchy-version-branch     -> git branch of ~/.nixos itself
  #   - omarchy-version-channel    -> the nixpkgs ref this flake is pinned
  #                                    to (e.g. "nixos-26.05"), read from
  #                                    flake.lock -- the closest real
  #                                    equivalent of an Arch "channel"
  #   - omarchy-theme-current       -> label changed to "matugen" (see
  #                                    home/matugen.nix); the ANSI color
  #                                    swatch itself is unchanged
  #   - omarchy-version-pkgs        -> was a pending-update count, which
  #                                    has no flake equivalent (updates are
  #                                    explicit, not queued); shows the
  #                                    last `nixos-rebuild switch` date
  #                                    instead (mtime of /run/current-system)
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        type = "file";
        source = logoPath;
        color."1" = "#7acdcd";
        padding = {
          top = 3;
          right = 6;
          left = 2;
        };
      };

      modules = [
        "break"
        {
          type = "custom";
          format = "${esc}[90m┌────────────────────Hardware───────────────────┐";
        }
        {
          type = "host";
          key = " PC ";
          keyColor = "#ff99da";
        }
        {
          type = "cpu";
          key = "│ ├ ";
          showPeCoreCount = true;
          keyColor = "#ff99da";
        }
        {
          type = "gpu";
          key = "│ ├ ";
          detectionMethod = "pci";
          keyColor = "#ff99da";
        }
        {
          type = "display";
          key = "│ ├󱄄 ";
          keyColor = "#ff99da";
        }
        {
          type = "disk";
          key = "│ ├󰋊 ";
          keyColor = "#ff99da";
        }
        {
          type = "memory";
          key = "│ ├ ";
          keyColor = "#ff99da";
        }
        {
          type = "swap";
          key = "└ └󰓡 ";
          keyColor = "#ff99da";
        }
        {
          type = "custom";
          format = "${esc}[90m└────────────────────────────────────────────────────┘";
        }
        "break"
        {
          type = "custom";
          format = "${esc}[90m┌──────────────────────Software──────────────────────┐";
        }
        {
          type = "command";
          key = " OS ";
          keyColor = "#7acdcd";
          text = "echo \"CoelOS $(nixos-version)\"";
        }
        {
          type = "command";
          key = "│ ├󰘬";
          keyColor = "#7acdcd";
          text = "git -C \"$HOME/.nixos\" rev-parse --abbrev-ref HEAD";
        }
        {
          type = "command";
          key = "│ ├󰔫";
          keyColor = "#7acdcd";
          text = ''grep -A15 "\"nixpkgs\": {" "$HOME/.nixos/flake.lock" | grep -m1 '"ref"' | sed -E 's/.*"ref": *"([^"]+)".*/\1/' '';
        }
        {
          type = "kernel";
          key = "│ ├ ";
          keyColor = "#7acdcd";
        }
        {
          type = "wm";
          key = "│ ├ ";
          keyColor = "#7acdcd";
        }
        {
          type = "de";
          key = " DE";
          keyColor = "#7acdcd";
        }
        {
          type = "terminal";
          key = "│ ├ ";
          keyColor = "#7acdcd";
        }
        {
          type = "packages";
          key = "│ ├󰏖 ";
          keyColor = "#7acdcd";
        }
        {
          type = "wmtheme";
          key = "│ ├󰉼 ";
          keyColor = "#7acdcd";
        }
        {
          type = "command";
          key = "│ ├󰸌 ";
          keyColor = "#7acdcd";
          text = "echo -e \"matugen ${esc}[38m●${esc}[37m●${esc}[36m●${esc}[35m●${esc}[34m●${esc}[33m●${esc}[32m●${esc}[31m●\"";
        }
        {
          type = "terminalfont";
          key = "└ └ ";
          keyColor = "#7acdcd";
        }
        {
          type = "custom";
          format = "${esc}[90m└────────────────────────────────────────────────────┘";
        }
        "break"
        {
          type = "custom";
          format = "${esc}[90m┌────────────────Age / Uptime / Update───────────────┐";
        }
        {
          type = "command";
          key = "󱦟 OS Age ";
          keyColor = "#ff99da";
          text = "echo $(( ($(date +%s) - $(stat -c %W /)) / 86400 )) days";
        }
        {
          type = "uptime";
          key = "󱫐 Uptime ";
          keyColor = "#ff99da";
        }
        {
          type = "command";
          key = " Update ";
          keyColor = "#ff99da";
          text = "stat -c %y /run/current-system | cut -d' ' -f1";
        }
        {
          type = "custom";
          format = "${esc}[90m└────────────────────────────────────────────────────┘";
        }
      ];
    };
  };

  xdg.configFile."fastfetch/ascii-logo.txt".text = builtins.readFile ./fastfetch/ascii-logo.txt;
}

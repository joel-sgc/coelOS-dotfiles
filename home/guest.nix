{ ... }:

# The guest account's desktop (modules/guest.nix): your Hyprland and Quickshell
# panel, built from the same modules, minus everything personal -- no git
# identity, calendar sync, webapp logins, VPN, server mount, Steam, KiCad or
# editor setup. The home is wiped at logout and this profile is written back.
#
# The shared modules reach the Quickshell config through ~/.nixos/home/quickshell
# (the launcher, power menu, screenshot tool, OSD and lock all use that path so
# edits hot-reload for you). The guest has no ~/.nixos, so that path is a
# symlink to the read-only copy in the Nix store: every one of those references
# works unchanged.
{
  imports = [
    ./quickshell.nix
    ./theme.nix
    ./cursor.nix
    ./qt-theme.nix
    ./ghostty.nix
    ./wallpaper.nix
    ./clipboard.nix
    ./hyprland.nix
    ./hypridle.nix
    ./os-commands.nix
    ./udiskie.nix
    ./kanshi.nix
    ./poweralertd.nix
    ./zen-browser.nix
    ./mimeapps.nix
  ];

  home.stateVersion = "26.05";

  home.file.".nixos/home/quickshell".source = ./quickshell;
}

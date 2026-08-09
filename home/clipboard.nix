{ config, pkgs, ... }:

{
  # Clipboard history. The old Arch config used a self-built tool
  # (clipvault); cliphist is the standard Wayland equivalent and needs no
  # extra packaging. History is plain text via `cliphist list`, so it's
  # accessible from anywhere (including piping into micro), not just rofi.
  # Picker is bound to SUPER+V in home/hyprland.nix.
  services.cliphist.enable = true;

  # Complements cliphist rather than duplicating it: native Wayland
  # clipboard content can vanish once the app you copied from exits (a
  # real, commonly-hit rough edge, not a hypothetical). cliphist only
  # covers *history* browsing via the picker; this keeps the live/current
  # clipboard selection alive for a plain Ctrl+V regardless. Its module
  # already respects wayland.systemd.target correctly out of the box, no
  # override needed here.
  services.wl-clip-persist = {
    enable = true;
    clipboardType = "both";
  };
}

# Nerd Font icons for the rofi menus (home/rofi.nix), defined once, by
# codepoint.
#
# Why codepoints and not the glyphs themselves: these are private-use
# characters, and an AI assistant that reads a file containing one can't see
# it (the text just shows a gap). Any time an assistant re-emits that text --
# a rewrite, or moving code between files -- the glyph is silently dropped
# and the menu label loses its icon, with no error anywhere. That's how the
# power menu lost its icons twice. Keeping the glyphs out of source files
# entirely, as plain ASCII codepoints here, makes that impossible: nothing is
# hidden, so nothing can be dropped.
#
# Scripts refer to an icon as @icon:<name>@ (see withIcons in home/rofi.nix),
# or as ${icons.<name>} in inline Nix strings. Names/codepoints were checked
# against the official Nerd Fonts glyph list; the official name is noted.
{ lib }:

let
  # Nix strings have no \u escape, but JSON does (with surrogate pairs above
  # U+FFFF), and builtins.fromJSON decodes it to UTF-8.
  esc = n: "\\u${lib.fixedWidthString 4 "0" (lib.toLower (lib.toHexString n))}";

  glyph =
    hex:
    let
      cp = lib.fromHexString hex;
      v = cp - 65536;
    in
    builtins.fromJSON ''"${
      if cp < 65536 then esc cp else esc (55296 + v / 1024) + esc (56320 + lib.mod v 1024)
    }"'';
in
builtins.mapAttrs (_: glyph) {
  # Main menu
  programs = "F003B"; # md-apps
  actions = "F14DE"; # md-rocket_launch
  settings = "F013"; # fa-cog
  rebuild = "F021"; # fa-refresh
  update = "F021"; # fa-refresh
  about = "F05A"; # fa-info_circle
  system = "F0906"; # md-power_standby

  # Power menu
  lock = "F023"; # fa-lock
  logout = "F0343"; # md-logout
  suspend = "F0904"; # md-power_sleep
  restart = "EAD2"; # cod-debug_restart
  power = "F0906"; # md-power_standby

  # Actions menu
  screenshot = "F0100"; # md-camera
  screen-record = "F03D"; # fa-video
  color = "F1FB"; # fa-eyedropper

  # Settings menu
  audio = "E638"; # seti-audio
  wifi = "F05A9"; # md-wifi
  bluetooth = "F00AF"; # md-bluetooth
  power-profiles = "F140B"; # md-lightning_bolt
  monitors = "F0379"; # md-monitor
  keybindings = "F11C"; # fa-keyboard
  input = "F037D"; # md-mouse
  fingerprint = "F0237"; # md-fingerprint
  config = "F013"; # fa-cog

  # Config menu
  hyprland = "F359"; # linux-hyprland
  autostart = "F14DE"; # md-rocket_launch
  window-rules = "F10AC"; # md-dock_window
  look-and-feel = "F03D8"; # md-palette
  waybar = "F0327"; # md-launch

  # Fingerprint menu. These two never had a recoverable icon in any
  # version -- they were already blank gaps when first written -- so
  # unlike everything above they're new picks, not restorations.
  enroll = "F0415"; # md-plus
  delete = "F01B4"; # md-delete
}

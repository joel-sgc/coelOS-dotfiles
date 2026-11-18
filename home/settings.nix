{ pkgs, ... }:

# `coel-settings`: read/edit/apply settings.toml (repo root) -- the file that
# holds quickly-changed settings (monitor layout, display scale, env, Hyprland
# options) so they need no rebuild. Hyprland reads it through
# home/hyprland/settings.lua; the quickshell Displays picker saves layouts
# into it through this CLI. See the header of settings.toml.
let
  coelSettings = pkgs.writeShellApplication {
    name = "coel-settings";
    runtimeInputs = [ pkgs.python3 ];
    # hyprctl comes from the system profile (programs.hyprland.enable).
    text = ''
      exec python3 ${./settings/coel_settings.py} "$@"
    '';
  };
in
{
  home.packages = [ coelSettings ];
}

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

  # Apply settings.toml whenever it is saved: Hyprland only reads it at config
  # load, so without this an edit does nothing until `coel-settings apply`.
  # systemd watches the file's directory, so editors that save by renaming a
  # temp file over it (and coel-settings itself) are caught too.
  systemd.user.paths.coel-settings-watch = {
    Unit.Description = "Watch settings.toml";
    Path = {
      PathChanged = "%h/.nixos/settings.toml";
      Unit = "coel-settings-apply.service";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  systemd.user.services.coel-settings-apply = {
    Unit = {
      Description = "Apply settings.toml to the running session";
      ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      # A burst of saves (editor autosave, picker + CLI) becomes one reload.
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "oneshot";
      Environment = "PATH=/run/current-system/sw/bin";
      # Let the writer finish and coalesce rapid saves before reloading.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 0.4";
      ExecStart = "${coelSettings}/bin/coel-settings apply";
    };
  };
}

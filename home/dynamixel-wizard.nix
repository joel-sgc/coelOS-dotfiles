{
  config,
  pkgs,
  lib,
  ...
}:

let
  dir = "${config.home.homeDirectory}/DYNAMIXEL Wizard 2.0";

  # DYNAMIXEL Wizard 2.0 isn't packaged in nixpkgs -- it's ROBOTIS's own
  # vendor Linux build, extracted by hand into ~/dynamixel-wizard, next to
  # a hand-written shell.nix there that builds the FHS sandbox (Qt5/X11/xcb
  # libs etc) the binary needs to actually run on NixOS. This wrapper just
  # launches the binary inside that same sandbox via `nix-shell --run` --
  # the standard way to run something non-interactively inside a
  # buildFHSEnv `.env` shell -- rather than duplicating shell.nix's package
  # list here, which would drift out of sync with it as that file gets
  # tweaked directly.
  runCmd = "cd ${lib.escapeShellArg dir} && exec ./DynamixelWizard2";

  launcher = pkgs.writeShellApplication {
    name = "coel-dynamixel-wizard";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      exec nix-shell ${lib.escapeShellArg "${dir}/shell.nix"} --run ${lib.escapeShellArg runCmd}
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "coel-dynamixel-wizard";
    desktopName = "DYNAMIXEL Wizard 2.0";
    genericName = "Dynamixel Servo Configuration Tool";
    icon = "${dir}/icon.png";
    exec = "coel-dynamixel-wizard";
    terminal = false;
    categories = [
      "Utility"
      "Engineering"
    ];
  };
in
{
  home.packages = [ launcher ];

  # Written to $XDG_DATA_HOME directly rather than through
  # xdg.desktopEntries -- same reasoning as home/desktop-entries.nix, see
  # that file's header comment.
  home.file.".local/share/applications/coel-dynamixel-wizard.desktop".source =
    "${desktopItem}/share/applications/coel-dynamixel-wizard.desktop";
}

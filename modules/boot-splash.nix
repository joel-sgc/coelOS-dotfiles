{ config, lib, pkgs, ... }:

# The boot splash (Plymouth, coelOS theme) and its handoff to the login screen.
# Kept apart from configuration.nix so tests/nixos/boot-seam-test.nix boots the
# same splash in a VM and checks that no black frame shows on the way to the
# greeter.
#
# No black between the splash and the login screen. Stock boot runs
# `plymouth quit` before the display manager, which wipes the splash and shows
# the blank console until cage and the greeter draw. Instead (as nixpkgs' GDM
# module does):
#   1. plymouth-quit doesn't run at boot; greetd starts while the splash is up.
#   2. greetd first runs `plymouth deactivate`: Plymouth stops drawing and lets
#      go of the display, its last frame staying on screen.
#   3. greetd doesn't reset VT1 to text mode (patches/greetd-keep-vt-mode.patch,
#      modules/greeter.nix), which would repaint the console over it.
#   4. cage's first frame replaces it: #282c34, not black
#      (patches/cage-coel-backdrop.patch), then the greeter draws.
#   5. Once the greeter is up (it touches /run/coel-hub/greeter-drawn),
#      coel-splash-handoff runs `plymouth quit --retain-splash`; Plymouth exits
#      without touching the screen. Plymouth must outlive cage's first frame:
#      if it exits while its framebuffer is still on screen, the kernel turns
#      the display off.
# If the greeter never reports in, the handoff gives up after 30 s with a plain
# `plymouth quit`, so a broken greeter shows a console rather than a frozen
# splash.
#
# Don't use `--retain-splash` with plymouth-quit at its stock place in boot:
# that left VT1 in graphics mode with no owner and the boot hung on a black
# screen (Nov 27 2026, back when the session hosts still switched VTs).
let
  plymouth = "${config.boot.plymouth.package}/bin/plymouth";
in
{
  boot.plymouth = {
    enable = true;
    theme = "coelos";
    themePackages = [
      (pkgs.stdenv.mkDerivation {
        pname = "coelos-plymouth-theme";
        version = "1.0";
        src = ../assets/plymouth-theme;

        installPhase = ''
          mkdir -p $out/share/plymouth/themes/coelos
          cp * $out/share/plymouth/themes/coelos/

          sed -i "s@^ImageDir=.*@ImageDir=$out/share/plymouth/themes/coelos@" $out/share/plymouth/themes/coelos/coelos.plymouth
          sed -i "s@^ScriptFile=.*@ScriptFile=$out/share/plymouth/themes/coelos/coelos.script@" $out/share/plymouth/themes/coelos/coelos.plymouth
        '';
      })
    ];
  };

  systemd.services.plymouth-quit.wantedBy = lib.mkForce [ ];

  # Drops greetd's stock wait for Plymouth to exit, which would now never end.
  services.greetd.greeterManagesPlymouth = true;
  systemd.services.greetd = {
    after = [ "plymouth-start.service" ];
    serviceConfig.ExecStartPre = [ "-${plymouth} deactivate" ];
    wants = [ "coel-splash-handoff.service" ];
    onFailure = [ "plymouth-quit.service" ];
  };

  systemd.services.coel-splash-handoff = {
    description = "Let Plymouth go once the login screen is up";
    after = [ "greetd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${plymouth} --ping || exit 0
      for _ in $(seq 300); do
        if [ -e /run/coel-hub/greeter-drawn ]; then
          exec ${plymouth} quit --retain-splash
        fi
        sleep 0.1
      done
      echo "the login screen never reported in; quitting the splash the plain way"
      exec ${plymouth} quit
    '';
  };
}

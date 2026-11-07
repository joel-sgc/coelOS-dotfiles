{ pkgs, ... }:

# Autodesk Fusion on Proton, using the installer from
# ~/Autodesk-Fusion-360-on-Linux (codeberg.org/cryinkfly/Autodesk-Fusion-360-on-Linux).
#
# Everything the installer, winetricks, Wine/Proton and Fusion itself write
# lives under ONE folder, ~/.autodesk_fusion. To get there, every wrapper
# below runs with HOME (and the XDG_* dirs) pointed at a fake home inside it:
#
#   ~/.autodesk_fusion/
#     home/    fake $HOME: .cache (winetricks, shader caches), .config,
#              .local/share (Wine menu/mime/icon junk, installer .desktop
#              files, installs.log), .local/share/Steam/compatibilitytools.d
#     bin/ downloads/ logs/ wineprefixes/ protonprefix/   (installer's own)
#
# Without this the installer scatters files over the real home: .desktop
# files + installs.log in ~/.local/share/applications/wine/, an
# `xdg-mime default` into ~/.config/mimeapps.list (a read-only home-manager
# file here, so it would just fail), winetricks' ~/.cache/winetricks, Wine's
# menu/mime/icon entries, and it launches Steam. Uninstall / reset after a
# failed install is simply:   rm -rf ~/.autodesk_fusion
#
# The only things outside it are declared below: the pinned Proton build
# (in the Nix store, symlinked into the fake home on each run), the three
# wrapper commands, one .desktop entry and the adskidmgr:// login handler.
#
# Usage:  fusion360-install   (once)      then launch "Autodesk Fusion"
# Steam is not needed or started (a no-op `steam` stub satisfies the
# installer/launcher, which otherwise start it in the background).

let
  protonName = "GE-Proton11-Fusion";
  repo = "$REAL_HOME/Autodesk-Fusion-360-on-Linux";

  protonFusion = pkgs.runCommand protonName
    {
      src = pkgs.fetchurl {
        url = "https://github.com/Lolig4/Autodesk-Fusion-360-for-Linux/releases/download/Pre_Build_Wine%2FProton_01.06.26/${protonName}.tar.gz";
        hash = "sha256-agUg+5JE9Hw6vf2V2IX8j/Nwc54htTsusp55kRr2wqs=";
      };
    }
    ''
      mkdir -p $out
      # Tarball's top-level dir is ${protonName}; flatten it into $out.
      tar -xf $src -C $out --strip-components=1
    '';

  # Tools the installer/launcher probe for (REQUIRED_COMMANDS in
  # check_required_packages). Present => it never takes its NixOS branch
  # (`sudo nix-env -iA ...`). Only on the wrappers' PATH, not the profile.
  tools = with pkgs; [
    curl
    wget
    gawk
    bc
    p7zip
    cabextract
    winetricks
    lsb-release
    mesa-demos # glxinfo
    polkit # pkexec
    samba # wbinfo
    systemd
    xrandr
    mokutil
    xdg-utils
    desktop-file-utils
    findutils
    procps # pgrep, free
    gettext # the installer wraps every message in `gettext`
    pciutils # lspci (GPU detection)
    util-linux # setsid
    ncurses # clear
    file
    coreutils
    gnugrep
    gnused
    gnutar
    gzip
  ];

  # Stubs that must win over what the FHS env puts first on PATH (its own
  # /usr/bin/steam is the REAL Steam, which the installer would otherwise
  # bootstrap inside the fake home). `wine` only answers --version: the
  # installer insists on a system wine >= 11.1 even in --proton mode and
  # otherwise runs `pkexec nix-env -iA nixos.wine`; it never uses it, as it
  # calls Proton's own wine by path.
  stubs = pkgs.symlinkJoin {
    name = "fusion360-stubs";
    paths = [
      (pkgs.writeShellScriptBin "steam" "exit 0")
      (pkgs.writeShellScriptBin "wine" ''
        case "$1" in --version) echo wine-11.1 ;; *) exit 1 ;; esac
      '')
    ];
  };

  # steam-run rebuilds PATH inside the FHS env, so the stubs have to be put
  # in front from in there.
  withStubs = pkgs.writeShellScript "fusion360-with-stubs" ''
    PATH="${stubs}/bin:$PATH"
    # Fusion compares the machine clock with Autodesk's UTC server time and
    # refuses to start ("Time mismatch with server") if they differ by >10
    # min. Under Wine its local->UTC conversion comes out with a zero offset
    # (the prefix registry has no TimeZoneInformation Bias), so a
    # non-UTC zone shows up as an hours-long error. Run everything in UTC.
    # Has to be set in here: steam-run's own init sets TZ to the host zone.
    export TZ=UTC
    exec "$@"
  '';
  inFhs = "steam-run ${withStubs}";

  # Shared prologue: enter the fake home and run the rest inside steam-run
  # (Proton's prebuilt binaries need an FHS userland on NixOS).
  jail = ''
    ROOT="$REAL_HOME/.autodesk_fusion"
    JAIL="$ROOT/home"
    mkdir -p "$JAIL/.local/share/Steam/compatibilitytools.d" \
             "$JAIL/.cache" "$JAIL/.config" "$JAIL/.local/state"
    ln -sfn ${protonFusion} "$JAIL/.local/share/Steam/compatibilitytools.d/${protonName}"
    # Wine opens the sign-in page through xdg-open, which reads the default
    # browser from $XDG_CONFIG_HOME/mimeapps.list -- an empty fake home has
    # none. Link in the real (home-manager managed) one, read-only use.
    ln -sfn "$REAL_HOME/.config/mimeapps.list" "$JAIL/.config/mimeapps.list"
    export HOME="$JAIL"
    export XDG_DATA_HOME="$JAIL/.local/share"
    export XDG_CONFIG_HOME="$JAIL/.config"
    export XDG_CACHE_HOME="$JAIL/.cache"
    export XDG_STATE_HOME="$JAIL/.local/state"
    # Belt and braces: never let Wine write menu/mime/icon entries at all.
    export WINEDLLOVERRIDES="winemenubuilder.exe=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
  '';

  mkWrapper = name: body: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = tools ++ [ pkgs.steam-run ];
    bashOptions = [ ]; # the upstream scripts are not set -e / -u clean
    text = ''
      REAL_HOME="$HOME"
      ${jail}
      ${body}
    '';
  };

  install = mkWrapper "fusion360-install" ''
    # Explicit dir, not --default: --default expands against $HOME, which is
    # now the fake home.
    exec ${inFhs} bash "${repo}/files/setup/autodesk_fusion_installer_x86-64.sh" \
      --proton=${protonName} "$ROOT" "$@"
  '';

  launch = mkWrapper "fusion360" ''
    exec ${inFhs} bash "$ROOT/bin/autodesk_fusion_launcher.sh" "$@"
  '';

  # adskidmgr:// sign-in callback (what the installer's adskidmgr-opener
  # .desktop does, minus the xdg-mime registration).
  idmgr = mkWrapper "fusion360-idmgr" ''
    PFX="$ROOT/protonprefix"
    EXE="$(find "$PFX/pfx" -name AdskIdentityManager.exe | head -1)"
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
    STEAM_COMPAT_DATA_PATH="$PFX" \
      exec ${inFhs} "$HOME/.local/share/Steam/compatibilitytools.d/${protonName}/proton" run "$EXE" "$@"
  '';

  fusionItem = pkgs.makeDesktopItem {
    name = "autodesk-fusion";
    desktopName = "Autodesk Fusion";
    genericName = "CAD Application";
    comment = "Cloud-based 3D modeling, CAD, CAM and PCB platform";
    exec = "fusion360";
    icon = "applications-engineering"; # Fusion's own icon stays inside the jail
    categories = [ "Education" "Engineering" "Graphics" "Science" ];
    startupNotify = true;
    startupWMClass = "fusion360.exe";
  };

  idmgrItem = pkgs.makeDesktopItem {
    name = "autodesk-fusion-idmgr";
    desktopName = "Autodesk Identity Manager";
    exec = "fusion360-idmgr %u";
    noDisplay = true;
    mimeTypes = [ "x-scheme-handler/adskidmgr" ];
  };
in
{
  home.packages = [ install launch idmgr ];

  # Written to $XDG_DATA_HOME directly rather than through
  # xdg.desktopEntries -- same reasoning as home/desktop-entries.nix.
  home.file.".local/share/applications/autodesk-fusion.desktop".source =
    "${fusionItem}/share/applications/autodesk-fusion.desktop";
  home.file.".local/share/applications/autodesk-fusion-idmgr.desktop".source =
    "${idmgrItem}/share/applications/autodesk-fusion-idmgr.desktop";

  xdg.mimeApps.defaultApplications."x-scheme-handler/adskidmgr" = [ "autodesk-fusion-idmgr.desktop" ];
}

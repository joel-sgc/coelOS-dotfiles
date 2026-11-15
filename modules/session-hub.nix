{ config, lib, pkgs, ... }:

# Session hub: one login screen that is also the lock screen.
#
#   VT1        the login screen ("hub"), always running -- the main greetd
#              (services.greetd, configured elsewhere) with the greeter UI.
#              It never starts a session itself.
#   VT7, VT8   session hosts: idle greetd instances. The hub authenticates the
#              user against a host and starts the session there; greetd
#              switches the screen to the host's VT. When the session ends the
#              host goes idle again.
#
# Leaving a session = switching to VT1 (the session stays alive, locked).
# Coming back = authenticate at the hub, then the hub lets the session's lock
# screen go (a token only the hub can write) and switches to it. coel-vt-guard bounces any switch into a session VT that did
# not come through the hub, so the hub is the only door.
#
# Why this shape: greetd ties a greeter and its session to one VT, so the hub
# cannot also be the session's VT. Splitting "the greeter" (VT1, permanent)
# from "where sessions run" (hosts) is what makes the hub instant: nothing
# has to start when you lock.
#
# Hosts use VT7+ on purpose: logind auto-spawns gettys only on VT1-6
# (NAutoVTs), so a getty can never land on a host's VT, and VT2-6 stay plain
# recovery consoles. The hub's own VT1 is handled by the stock greetd module.
#
# Off by default; nothing changes until services.coel-hub.enable is set.

let
  cfg = config.services.coel-hub;
  vts = lib.concatMapStringsSep " " toString cfg.hostVts;

  python = "${pkgs.python3}/bin/python3";

  hubClient = pkgs.writeScriptBin "coel-hub" ''
    #!${python}
    ${builtins.readFile ../scripts/coel-hub.py}
  '';
  # writeScriptBin only substitutes the shebang; the env var carries the VTs.
  hubClientWrapped = pkgs.symlinkJoin {
    name = "coel-hub";
    paths = [ hubClient ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/coel-hub \
        --set COEL_HOST_VTS "${vts}" \
        --set COEL_LOCK_CMD ${lib.escapeShellArg cfg.lockCommand} \
        --prefix PATH : ${lib.makeBinPath [ pkgs.systemd pkgs.libnotify ]}
    '';
  };

  guardScript = pkgs.writeScript "coel-vt-guard" ''
    #!${python}
    ${builtins.readFile ../scripts/coel-vt-guard.py}
  '';

  hostUnit = vt: "greetd-host-${toString vt}";

  hostConfig = vt: pkgs.writeText "greetd-host-${toString vt}.toml" ''
    [terminal]
    vt = ${toString vt}

    # Idle until the hub starts a session here. greetd needs *some* greeter to
    # keep running; this one does nothing, so an idle host costs no compositor
    # and no UI.
    [default_session]
    command = "${pkgs.coreutils}/bin/sleep infinity"
    user = "greeter"
  '';
in
{
  options.services.coel-hub = {
    enable = lib.mkEnableOption "the session hub (login screen on VT1, sessions on other VTs)";

    lockCommand = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.quickshell}/bin/quickshell -p ~/.nixos/home/quickshell/lock-real-shell.qml";
      defaultText = lib.literalExpression ''"''${pkgs.quickshell}/bin/quickshell -p ~/.nixos/home/quickshell/lock-real-shell.qml"'';
      description = ''
        Starts the in-session lock screen (run through sh, so ~ expands). It
        must create "$XDG_RUNTIME_DIR/coel-lock-ready-$XDG_SESSION_ID" once the
        compositor has confirmed the lock, and exit when
        /run/coel-hub/unlock/$XDG_SESSION_ID exists and is NEWER than that
        marker (so a leftover grant never unlocks a later lock).
      '';
    };

    hubBlankAfter = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = ''
        Seconds without input at the login screen before the laptop backlight
        goes to 0 (any input brings it back). 0 turns it off. External monitors
        have no backlight to switch and stay lit.
      '';
    };

    hubSuspendAfter = lib.mkOption {
      type = lib.types.int;
      default = 600;
      description = ''
        Seconds without input at the login screen before the machine suspends.
        0 turns it off. Together with the session's own idle lock (10 minutes in
        home/hypridle.nix) a machine left alone suspends after about 20.
      '';
    };

    hostVts = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ 7 8 ];
      description = ''
        VTs of the session hosts: how many sessions can run at once. Keep them
        above 6 (see the header comment).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ hubClientWrapped ];

    # One unit per host, started strictly one after the other, the hub last.
    #
    # Why not one template started three times at once: greetd switches to its
    # VT and then BLOCKS until that VT is on screen (VT_SETACTIVATE +
    # VT_WAITACTIVE). Started together, their switches race; the one whose
    # switch is overtaken waits for a VT that never comes, and that host can
    # never hold a session. (The VM test hung at boot in 2 runs of 5.) So each
    # host's start only completes (ExecStartPost) once its idle greeter is up
    # and the screen has moved on -- coel-vt-guard does that move -- and the
    # next host, then the hub, starts after it.
    systemd.services = lib.mkMerge [
      (lib.listToAttrs (lib.imap0
        (i: vt: lib.nameValuePair (hostUnit vt) {
          description = "Session host on VT ${toString vt}";
          unitConfig = {
            Wants = [ "systemd-user-sessions.service" "coel-vt-guard.service" ];
            After = [ "systemd-user-sessions.service" "plymouth-quit-wait.service" "coel-vt-guard.service" ]
              ++ lib.optional (i > 0) "${hostUnit (builtins.elemAt cfg.hostVts (i - 1))}.service";
          };
          serviceConfig = {
            ExecStart = "${lib.getExe config.services.greetd.package} --config ${hostConfig vt}";
            ExecStartPost = "-${hubClientWrapped}/bin/coel-hub wait-host ${toString vt}";
            Type = "simple";
            Restart = "on-failure";
            # As the stock greetd unit.
            IgnoreSIGPIPE = false;
            SendSIGHUP = true;
            TimeoutStopSec = "30s";
            KeyringMode = "shared";
          };
          # Stopping a host logs out whoever is on it, so a rebuild must never
          # touch a running one.
          restartIfChanged = false;
          stopIfChanged = false;
          wantedBy = [ "graphical.target" ];
        })
        cfg.hostVts))

      {
        coel-vt-guard = {
          description = "Bounce unauthorised VT switches into sessions back to the login screen";
          wantedBy = [ "multi-user.target" ];
          environment = {
            COEL_GUARDED_VTS = vts;
            COEL_HUB_BLANK_AFTER = toString cfg.hubBlankAfter;
            COEL_HUB_SUSPEND_AFTER = toString cfg.hubSuspendAfter;
          };
          serviceConfig = {
            ExecStart = guardScript;
            # Never leave the screen dark: the saved brightness survives an
            # automatic restart, and is put back whenever the daemon stops.
            ExecStopPost = "${guardScript} --restore";
            RuntimeDirectory = "coel-vt-guard";
            RuntimeDirectoryPreserve = "restart";
            Restart = "always";
            RestartSec = 1;
          };
        };
      }

      # The hub (the main greetd) comes up last, so it ends up on screen.
      {
        greetd = {
          after = map (vt: "${hostUnit vt}.service") cfg.hostVts;
          wants = map (vt: "${hostUnit vt}.service") cfg.hostVts;
        };
      }
    ];

    # Switching VTs (loginctl activate) goes through logind's polkit
    # check; without polkit logind only accepts root.
    security.polkit.enable = lib.mkDefault true;

    # Where the hub leaves its tokens: "this VT switch is authorised" (read by
    # the guard) and "this session may unlock" (read by the session's lock
    # screen). World-readable, greeter-writable: programs running as a normal
    # user can see them but must never be able to create one.
    systemd.tmpfiles.rules = [
      "d /run/coel-hub 0755 greeter greeter -"
      "d /run/coel-hub/unlock 0755 greeter greeter -"
    ];

  };
}

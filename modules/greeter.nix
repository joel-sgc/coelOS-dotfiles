{ config, lib, pkgs, ... }:

let
  cfg = config.services.qs-greeter;

  quickshellSrc = ../home/quickshell;
  phosphorFont = import ../home/quickshell-phosphor-font.nix { inherit pkgs; };

  # Users shown in the greeter -- normal (human) accounts only. The
  # greeter never reads /etc/passwd or anyone's home directory itself,
  # matching the "declared in Nix, read-only at runtime" goal.
  usersJson = pkgs.writeText "qs-greeter-users.json" (builtins.toJSON (
    lib.mapAttrsToList (name: u: {
      inherit name;
      displayName = if (u.description or "") != "" then u.description else name;
    }) (lib.filterAttrs (_: u: u.isNormalUser) config.users.users)
  ));

  # Sessions discovered from the real wayland-sessions/*.desktop files NixOS
  # installs (config.services.displayManager.sessionData.desktops), so
  # Hyprland/Plasma entries always match what's actually configured rather
  # than being hand-maintained here.
  sessionsJson = pkgs.runCommand "qs-greeter-sessions.json"
    { nativeBuildInputs = [ pkgs.jq ]; } ''
      dir=${config.services.displayManager.sessionData.desktops}/share/wayland-sessions
      for f in "$dir"/*.desktop; do
        [ -e "$f" ] || continue
        id=$(basename "$f" .desktop)
        name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
        exec=$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | sed -E 's/ ?%[a-zA-Z]//g')
        # The real DesktopNames= value, not our own filename-derived id --
        # Plasma's session fails to start without XDG_CURRENT_DESKTOP set
        # to its real expected value ("KDE", not "plasma"): portals, Qt
        # platform theming, and KDE component detection all key off it,
        # unlike Hyprland's own startup script, which corrects it itself.
        desktopNames=$(grep -m1 '^DesktopNames=' "$f" | cut -d= -f2-)
        jq -n --arg id "$id" --arg n "$name" --arg e "$exec" --arg d "$desktopNames" \
          '{id:$id, name:$n, exec:$e, desktopNames:$d}'
      done | jq -s . > $out
    '';

  # The complete greeter Quickshell config, self-contained in the Nix
  # store -- the greeter runs as an unprivileged `greeter` system user with
  # no access to /home/joelsgc, so it can't share the lock screen's live
  # repo path the way lock-real-shell.qml does. Copies the lock screen's
  # own component source (home/quickshell/lock/, plus its Phosphor.js/
  # wordmark deps) so the greeter and lock screen stay visually identical,
  # per Greeter.qml's `import "../lock"`.
  greeterConfig = pkgs.runCommand "qs-greeter-config" { } ''
    mkdir -p $out/sysPanel $out/assets
    cp -r ${quickshellSrc}/greeter $out/greeter
    cp -r ${quickshellSrc}/lock $out/lock
    cp ${quickshellSrc}/sysPanel/Phosphor.js $out/sysPanel/Phosphor.js
    cp ${quickshellSrc}/assets/coelos-wordmark.png $out/assets/coelos-wordmark.png
    cp ${quickshellSrc}/greeter-shell.qml $out/shell.qml
  '';

  greeterLauncher = pkgs.writeShellScript "qs-greeter" ''
    export XKB_DEFAULT_LAYOUT=${config.services.xserver.xkb.layout}
    export QT_QPA_PLATFORM=wayland
    export XDG_CACHE_HOME=/var/lib/qs-greeter/cache
    # cage's stdout/stderr (kept via -d for troubleshooting) caused a brief
    # flash of console text right at cage startup since nothing is
    # compositing over the console yet -- routed to a log file the same way
    # GreeterBackend.qml's doLaunch() redirects the launched session.
    exec >/tmp/qs-greeter-cage.log 2>&1
    # Force logind, not seatd: libseat tries seatd first whenever
    # /run/seatd.sock exists, but seatd was only ever added to fix a
    # VM-only "socket missing" error -- on real hardware it left cage with
    # zero real outputs instead. logind is what this laptop's Hyprland/
    # Plasma sessions already use successfully every day.
    export LIBSEAT_BACKEND=logind
    # Brief delay before the client connects: cage execs its child right
    # after starting its own backend, but wlroots' DRM connector
    # enumeration (the real eDP-1 discovery) may not finish until a later
    # event-loop iteration, and quickshell's own Wayland roundtrip is fast
    # enough to lose that race, logging "There are no outputs" every time.
    # Giving cage's backend a moment to finish first avoids it.
    exec ${pkgs.cage}/bin/cage -s -d -- \
      ${pkgs.bash}/bin/bash -c "sleep 1; exec ${pkgs.quickshell}/bin/quickshell -p ${greeterConfig}"
  '';
in
{
  # Importing this file is a no-op on its own (SDDM keeps running) until
  # services.qs-greeter.enable is explicitly set true elsewhere -- this
  # module replaces the login manager entirely, too high-stakes a flip to
  # risk an unrelated rebuild picking it up silently just by being imported.
  options.services.qs-greeter.enable = lib.mkEnableOption ''
    the Quickshell-based greetd login screen (home/quickshell/greeter/),
    replacing SDDM
  '';

  config = lib.mkIf cfg.enable {
    # The previous (SDDM-based) generation stays in the bootloader menu as
    # the real fallback if this regresses -- SDDM and greetd would contend
    # for the same VT if both were enabled at once.
    services.displayManager.sddm.enable = lib.mkForce false;

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${greeterLauncher}";
        user = "greeter";
      };
    };

    # greetd's own unit defaults to Type=idle, which defers execution until
    # all other boot jobs are dispatched (systemd's documented behavior,
    # capped at 5s) to avoid interleaving console output -- SDDM's splash
    # covers that gap, but cage has nothing covering it, so it showed as a
    # plain black screen instead. Session-launch output is already
    # redirected to a log file (GreeterBackend.qml doLaunch()), so the
    # interleaving concern Type=idle guards against doesn't apply here.
    systemd.services.greetd.serviceConfig.Type = lib.mkForce "simple";

    environment.etc."qs-greeter/users.json".source = usersJson;
    environment.etc."qs-greeter/sessions.json".source = sessionsJson;

    # cage (a wlroots compositor, like Hyprland) needs real seat access for
    # input/DRM permissions -- without this, libseat fails outright and
    # "Terminate Plymouth Boot Screen" hangs waiting on a display manager
    # that never becomes ready.
    services.seatd.enable = true;
    users.users.greeter.extraGroups = [ "seat" ];

    # Writable state for a future "remember last user/session" feature
    # only -- not used yet, reserved so adding it later doesn't need a
    # fresh tmpfiles rule.
    systemd.tmpfiles.rules = [
      "d /var/lib/qs-greeter 0755 greeter greeter -"
    ];

    # The greeter user has no ~/.local/share/fonts -- these must be
    # system-wide for it to render at all.
    fonts.packages = [ pkgs.jetbrains-mono phosphorFont ];

    # Same gnome-keyring PAM integration configuration.nix already sets
    # for sddm, mirrored here for parity now that greetd is what actually
    # starts the session.
    security.pam.services.greetd.enableGnomeKeyring = true;

    # Password FIRST, then fingerprint as a second required factor.
    #
    # fprintd used to be `sufficient` and first in this stack, so a good scan
    # ended authentication before pam_unix ever saw the password -- and
    # pam_gnome_keyring (which unlocks the login keyring from that password)
    # never got it, leaving the keyring locked on every fingerprint login.
    # Now pam_unix (the "unix-early" rule) takes the password first,
    # gnome_keyring uses it, then fprintd must also pass, then the final
    # pam_unix (try_first_pass) actually verifies the password. A wrong
    # password still fails (that last pam_unix, then pam_deny), just after the
    # fingerprint step.
    #
    # The control value: success/unavailable fall through, anything else marks
    # the stack failed but keeps going (so the failure isn't skipped over by
    # the later `sufficient` pam_unix). authinfo_unavail=ignore means an
    # account with no enrolled finger (or fprintd down) still logs in with
    # just its password instead of being locked out.
    #
    # GreeterBackend.qml answers the one password prompt, then shows
    # fprintd's "place your finger" text as a status line.
    security.pam.services.greetd.rules.auth.fprintd = {
      order = config.security.pam.services.greetd.rules.auth.gnome_keyring.order + 10;
      control = lib.mkForce "[success=ok authinfo_unavail=ignore default=bad]";
    };
  };
}

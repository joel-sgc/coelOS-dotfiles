{ config, lib, pkgs, ... }:

let
  cfg = config.services.qs-greeter;

  quickshellSrc = ../home/quickshell;
  phosphorFont = import ../home/quickshell-phosphor-font.nix { inherit pkgs; };

  # Users shown in the greeter -- normal (human) accounts only. The
  # greeter never reads /etc/passwd or anyone's home directory itself,
  # matching the "declared in Nix, read-only at runtime" goal.
  usersJson = pkgs.writeText "qs-greeter-users.json" (builtins.toJSON (
    lib.sort (a: b: (if a.passwordless then 1 else 0) < (if b.passwordless then 1 else 0) || (a.passwordless == b.passwordless && a.name < b.name)) (lib.mapAttrsToList (name: u: {
      inherit name;
      displayName = if (u.description or "") != "" then u.description else name;
      # An empty password (the guest): the login screen lets Enter through.
      passwordless = (u.hashedPassword or null) == "";
    }) (lib.filterAttrs (_: u: u.isNormalUser) config.users.users))
  ));

  # Sessions discovered from the real wayland-sessions/*.desktop files NixOS
  # installs (config.services.displayManager.sessionData.desktops), so
  # the Hyprland entries always match what's actually configured rather
  # than being hand-maintained here.
  sessionsJson = pkgs.runCommand "qs-greeter-sessions.json"
    { nativeBuildInputs = [ pkgs.jq ]; } ''
      dir=${config.services.displayManager.sessionData.desktops}/share/wayland-sessions
      for f in "$dir"/*.desktop; do
        [ -e "$f" ] || continue
        id=$(basename "$f" .desktop)
        name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
        exec=$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | sed -E 's/ ?%[a-zA-Z]//g')
        # The real DesktopNames= value, not our own filename-derived id.
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
    # Globals.qml (home/quickshell/Globals.qml) -- lock/components/
    # (AuthCard.qml, MediaWidget.qml) reads Globals.eyeCandyOff for its
    # rounding, via the root-relative `import "../.."` every file outside
    # home/quickshell/ itself needs to reach that singleton. Without it
    # also present at $out's root, that import resolves to nothing,
    # "Globals" is undefined, and the whole greeter UI fails to load --
    # confirmed live as a black screen with a blinking cursor (cage
    # running, quickshell crashed on top of it).
    #
    # Not a straight copy of home/quickshell/qmldir: that one also lists
    # Border/Launcher/Notifications/Osd/Polkit/Widgets, none of which
    # exist in this derivation's $out (only greeter/, lock/, and the two
    # asset files above are copied) -- a qmldir entry pointing at a
    # missing file would just trade one load failure for another. This
    # greeter root only ever needs the one singleton.
    cp ${quickshellSrc}/Globals.qml $out/Globals.qml
    echo 'singleton Globals 1.0 Globals.qml' > $out/qmldir
  '';

  # One Dark backdrop instead of black, shown from cage's very first frame, so
  # the boot splash goes straight to that colour (modules/boot-splash.nix), with
  # the splash's wordmark on it until the greeter maps; and no default pointer
  # (the greeter sets its own once the mouse moves).
  # The boot splash's wordmark as raw pixels for that cage (premultiplied
  # ARGB8888, i.e. BGRA bytes; flattened onto the backdrop so alpha is 255).
  # Same file Plymouth draws, centred the same way, so the handoff is invisible.
  cageSplash = pkgs.runCommand "coel-cage-splash.bgra" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    magick ${../assets/plymouth-theme/logo.png} -background '#282c34' -flatten -depth 8 BGRA:$out
  '';
  cage = pkgs.cage.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/cage-coel-backdrop.patch ];
  });

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
    # Hyprland sessions already use successfully every day.
    export LIBSEAT_BACKEND=logind
    # Software cursor only: with the hardware cursor plane, cage leaves the
    # cursor sprite programmed on the display after the VT switch (its CRTC
    # disable fails), and the session's compositor never clears it, so a ghost
    # pointer stays on screen.
    export WLR_NO_HARDWARE_CURSORS=1
    # The splash wordmark cage shows until the greeter's first frame.
    export COEL_CAGE_SPLASH=${cageSplash} COEL_CAGE_SPLASH_W=730 COEL_CAGE_SPLASH_H=160
    # Quickshell must not connect before cage advertises an output (it logs
    # "There are no outputs" and shows nothing). This used to be a fixed
    # `sleep 1`, which was most of the black gap between the boot splash and
    # the login screen; now poll for a wl_output (normally there at once) and
    # start as soon as one exists, giving up after 2 s.
    #
    # Plain extend (cage's default -- no -m flag needed): confirmed live
    # that "-m last" is NOT "use eDP-1", it's "use whichever output was
    # most recently connected" (cage -h's own wording) -- on this laptop
    # eDP-1 is connected before any external monitor, so "last" actually
    # picked the external monitor instead, showing the greeter there
    # instead of the laptop panel. cage 0.3.0 has no flag to target a
    # specific named output at all (confirmed via cage -h: just
    # extend/last, nothing else), so there's no way to ask it for eDP-1
    # directly. Back to extend's combined bounding box across every
    # connected output instead, with Greeter.qml now sizing its window to
    # that whole combined box and positioning the actual UI within just
    # eDP-1's own sub-rectangle inside it (see its own comment) -- rather
    # than fighting cage's output selection, which this cage version
    # simply doesn't expose.
    exec ${cage}/bin/cage -s -d -- \
      ${pkgs.bash}/bin/bash -c "for i in \$(${pkgs.coreutils}/bin/seq 40); do ${pkgs.wayland-utils}/bin/wayland-info -i wl_output 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q \"interface: .wl_output\" && break; ${pkgs.coreutils}/bin/sleep 0.05; done; exec ${pkgs.quickshell}/bin/quickshell -p ${greeterConfig}"
  '';
in
{
  # Importing this file is a no-op on its own until
  # services.qs-greeter.enable is explicitly set true elsewhere -- this
  # module is the login manager, too high-stakes a flip to risk an
  # unrelated rebuild picking it up silently just by being imported.
  options.services.qs-greeter.enable = lib.mkEnableOption ''
    the Quickshell-based greetd login screen (home/quickshell/greeter/)
  '';

  config = lib.mkIf cfg.enable {
    services.greetd = {
      enable = true;
      # Leaves VT1's mode alone instead of forcing text mode, which would
      # repaint the console over the boot splash (modules/boot-splash.nix).
      # The session hosts' greetd (modules/session-hub.nix) builds on this one.
      package = pkgs.greetd.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../patches/greetd-keep-vt-mode.patch ];
      });
      settings.default_session = {
        command = "${greeterLauncher}";
        user = "greeter";
      };
    };

    # greetd's own unit defaults to Type=idle, which defers execution until
    # all other boot jobs are dispatched (systemd's documented behavior,
    # capped at 5s) to avoid interleaving console output -- cage has nothing
    # covering that gap, so it showed as a plain black screen. Session-launch output is already
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

    # gnome-keyring PAM integration, so the login keyring unlocks with the
    # password typed at the greeter.
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

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
  # actually installs (confirmed real option on this channel:
  # config.services.displayManager.sessionData.desktops), so Hyprland/
  # Plasma entries always match what's actually configured rather than
  # being hand-maintained here.
  sessionsJson = pkgs.runCommand "qs-greeter-sessions.json"
    { nativeBuildInputs = [ pkgs.jq ]; } ''
      dir=${config.services.displayManager.sessionData.desktops}/share/wayland-sessions
      for f in "$dir"/*.desktop; do
        [ -e "$f" ] || continue
        id=$(basename "$f" .desktop)
        name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
        exec=$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | sed -E 's/ ?%[a-zA-Z]//g')
        jq -n --arg id "$id" --arg n "$name" --arg e "$exec" \
          '{id:$id, name:$n, exec:$e}'
      done | jq -s . > $out
    '';

  # The complete greeter Quickshell config, self-contained in the Nix
  # store -- the greeter runs as an unprivileged, separate `greeter`
  # system user with no access to /home/joelsgc, so it can't share the
  # interactive lock screen's live repo path the way lock-real-shell.qml
  # does. Copies the exact same component source the lock screen uses
  # (home/quickshell/lock/, plus the sysPanel/Phosphor.js and
  # assets/coelos-wordmark.png it depends on) rather than a separate/
  # parallel visual design -- this is what keeps the greeter and lock
  # screen looking identical, per Greeter.qml's own `import "../lock"`.
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
    # cage's own stdout/stderr (its -d debug logging, kept for future
    # troubleshooting rather than dropped outright) were never redirected
    # before -- confirmed live (real hardware) that this was the source
    # of a brief flash of console text right as cage starts, since
    # nothing is compositing over the console yet at that point. Routed
    # to a log file the same way GreeterBackend.qml's doLaunch() already
    # redirects the launched session's own output.
    exec >/tmp/qs-greeter-cage.log 2>&1
    # Force logind, not seatd -- confirmed live (real hardware, a clean
    # cold boot with nothing else competing for the seat) that cage still
    # got zero real outputs ("There are no outputs - creating placeholder
    # screen", then eglSwapBuffers failing on a literal null surface),
    # even with no DRM-master contention at all. libseat tries the seatd
    # backend before logind whenever /run/seatd.sock exists, and seatd
    # was only ever added here to fix a *VM-only* "socket missing" error
    # (real hardware never hit that). logind is what this laptop's actual
    # Hyprland/Plasma sessions already use successfully every day, so
    # forcing it here removes an untested seat backend from the one path
    # that's actually been failing.
    export LIBSEAT_BACKEND=logind
    # A brief delay before the client connects -- confirmed live (real
    # hardware, a genuinely clean single-compositor boot, logind seat
    # backend, only one real DRM device with eDP-1 actually connected)
    # that quickshell still logs "There are no outputs - creating
    # placeholder screen" every single time, deterministically. DRM
    # contention, seatd-vs-logind, and a missing/wrong DRM device have
    # all been ruled out directly on this hardware. What's left: cage
    # forks/execs its child immediately after starting its own backend,
    # but wlroots' DRM connector enumeration (the actual eDP-1 discovery
    # that creates the real wl_output global) may not complete until a
    # later event-loop iteration -- quickshell's own Wayland roundtrip is
    # fast enough to always lose that race. Giving cage's own backend a
    # moment to finish before the client even connects is the cheapest
    # way to test that theory.
    exec ${pkgs.cage}/bin/cage -s -d -- \
      ${pkgs.bash}/bin/bash -c "sleep 1; exec ${pkgs.quickshell}/bin/quickshell -p ${greeterConfig}"
  '';
in
{
  # Importing this file is a no-op on its own -- nothing here takes effect
  # (SDDM keeps running exactly as it does today) until
  # services.qs-greeter.enable is explicitly set true elsewhere. This is
  # deliberate: the module itself replaces the login manager (SDDM ->
  # greetd), which is a meaningfully higher-stakes flip than anything
  # else added this way in this repo so far, and it shouldn't be possible
  # for some later, unrelated `nixos-rebuild switch` to pick this up
  # silently just because the file is present in `imports`.
  options.services.qs-greeter.enable = lib.mkEnableOption ''
    the Quickshell-based greetd login screen (home/quickshell/greeter/),
    replacing SDDM
  '';

  config = lib.mkIf cfg.enable {
    # The previous (SDDM-based) generation stays in the bootloader menu as
    # the real fallback if this ever regresses -- a display manager can't
    # coexist-but-unused within one generation the way hyprlock could
    # (both would contend for the same VT if enabled together).
    services.displayManager.sddm.enable = lib.mkForce false;

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${greeterLauncher}";
        user = "greeter";
      };
    };

    # greetd's own unit defaults to Type=idle -- confirmed live (real
    # hardware, precise journal timestamps) that this delays greetd
    # actually starting by ~6 seconds after "Started greetd.service" is
    # logged, matching systemd's own documented behavior for Type=idle:
    # execution is deferred until all other boot jobs are dispatched,
    # capped at a hardcoded 5s timeout either way. That's meant to avoid
    # interleaving console output between services starting in parallel
    # at boot -- SDDM never showed this gap because its own splash
    # covers the console immediately, but cage has nothing covering it,
    # so the deferral shows up as a plain black screen. Session-launch
    # output is already redirected to a log file (see GreeterBackend.qml
    # doLaunch()), so the interleaving Type=idle guards against is no
    # longer a real concern here.
    systemd.services.greetd.serviceConfig.Type = lib.mkForce "simple";

    environment.etc."qs-greeter/users.json".source = usersJson;
    environment.etc."qs-greeter/sessions.json".source = sessionsJson;

    # cage (a wlroots compositor, like Hyprland) needs real seat access to
    # get input/DRM permissions -- confirmed live in VM testing: without
    # this, libseat fails with "Could not connect to socket
    # /run/seatd.sock: No such file or directory", cage/quickshell never
    # actually render, and "Terminate Plymouth Boot Screen" hangs forever
    # waiting on a display manager that never becomes ready. Not a VM-only
    # quirk -- libseat tries seatd before logind here, so real hardware
    # would hit the exact same failure without this.
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

    # Same fprintAuth-disable configuration.nix already applies to the
    # lock screen's own PAM services -- confirmed live (real hardware)
    # that without it, greetd's PAM stack tries fprintd before unix auth
    # automatically, so a typed password just sits queued behind an
    # unrequested "place your finger" step (which GreeterBackend.qml
    # never shows UI for -- fpOn is hardcoded false there) until it times
    # out, making password login look broken while a finger on the
    # sensor completes instantly. This greeter has no real fingerprint
    # UI wired up yet, so disable it here the same way, rather than
    # silently depending on an accidental PAM ordering.
    security.pam.services.greetd.fprintAuth = false;
  };
}

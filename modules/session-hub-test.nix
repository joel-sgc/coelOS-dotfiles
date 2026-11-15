{ pkgs, ... }:

# Headless check of the session hub mechanics (modules/session-hub.nix): the
# VT handling, the greetd host protocol, logind unlock and the VT guard. No
# graphics: the "hub" is a stub and the "session" is a long sleep -- what is
# under test is who may show what on which VT, not any UI.
#
#   nix build --impure --expr \
#     'let f = builtins.getFlake "git+file://$PWD"; pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; };
#      in pkgs.testers.runNixOSTest ./modules/session-hub-test.nix'
{
  name = "session-hub";

  nodes.machine = { pkgs, ... }: {
    imports = [ ./session-hub.nix ./guest.nix ];

    services.coel-hub.enable = true;
    # Short timers so idle behaviour can be watched; a fake backlight, a fake
    # input pipe (one 24-byte input_event per key press) and a fake "suspend".
    services.coel-hub.hubBlankAfter = 6;
    services.coel-hub.hubSuspendAfter = 24;
    systemd.services.coel-vt-guard.environment = {
      COEL_BL_DIR = "/run/fake-bl";
      COEL_INPUT_DIR = "/run/fake-input";
      COEL_SUSPEND_CMD = "touch /run/suspend-called";
      COEL_INHIBIT_DIR = "/run/fake-inhibit";
    };
    systemd.tmpfiles.rules = [
      "d /run/fake-bl/panel 0755 root root -"
      "f /run/fake-bl/panel/brightness 0644 root root - 80"
      "f /run/fake-bl/panel/max_brightness 0644 root root - 100"
      "d /run/fake-inhibit 0755 root root -"
      "d /run/fake-input 0755 root root -"
      "p /run/fake-input/event0 0666 root root -"
    ];

    # Stand-in for the Quickshell lock screen, same contract: drop a marker
    # once "locked", exit when the hub's fresh grant file for this session
    # appears.
    services.coel-hub.lockCommand = "${pkgs.writeShellScript "lock-stub" ''
      touch "$XDG_RUNTIME_DIR/coel-lock-ready-$XDG_SESSION_ID"
      f=/run/coel-hub/unlock/$XDG_SESSION_ID
      m="$XDG_RUNTIME_DIR/coel-lock-ready-$XDG_SESSION_ID"
      while :; do
        if [ -n "$(${pkgs.findutils}/bin/find "$f" -newer "$m" 2>/dev/null)" ]; then break; fi
        sleep 0.3
      done
    ''}";

    # Stub hub on VT1: the real one is the Quickshell greeter.
    services.greetd = {
      enable = true;
      settings.default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
    };

    # The guest: RAM home, wiped at logout. The seed tree mimics what a
    # home-manager profile looks like in the store: symlink-ish files inside
    # READ-ONLY directories (the guest must still be able to write there).
    services.coel-guest = {
      enable = true;
      homeModule = null;
      seedFrom = pkgs.runCommand "guest-seed" { } ''
        mkdir -p $out/.config/app
        echo profile > $out/.seeded
        echo cfg > $out/.config/app/settings
        chmod 555 $out/.config/app
      '';
    };
    networking.nftables.enable = true;
    # The VM framework replaces `fileSystems` wholesale, which would silently drop
    # the guest module's own tmpfs mount, so the same mount is given here (the
    # real fstab line is checked in the system build).
    virtualisation.fileSystems."/home/guest" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0700" "uid=1100" "gid=1100" "size=256M" "nosuid" "nodev" ];
    };

    users.users.alice = {
      isNormalUser = true;
      password = "secret";
    };
    users.users.mallory = {
      isNormalUser = true;
      password = "hunter2";
    };

    environment.systemPackages = [ pkgs.jq ];
    virtualisation.memorySize = 1024;
  };

  testScript = ''
    import json
    import time

    def active_vt():
        return machine.succeed("cat /sys/class/tty/tty0/active").strip()

    def sessions():
        return json.loads(machine.succeed("loginctl list-sessions --json=short"))

    def session_on(tty, cls):
        return next((s for s in sessions() if s["tty"] == tty and s["class"] == cls), None)

    def in_session(sid, user, cmd, stdin=""):
        # Run `cmd` as `user` INSIDE logind session `sid` (its cgroup), like a
        # keybind or the login screen's own process would. A bare `runuser`
        # from this root shell belongs to no session, which polkit treats
        # very differently ("not an active local session"). The command goes
        # through a script file so no quoting can leak into the root shell.
        uid = machine.succeed(f"id -u {user}").strip()
        scope = f"/sys/fs/cgroup/user.slice/user-{uid}.slice/session-{sid}.scope/cgroup.procs"
        machine.succeed(f"cat > /tmp/in-session.sh <<'EOS'\n{cmd}\nEOS\nchmod 755 /tmp/in-session.sh")
        return machine.execute(
            f"echo '{stdin}' | sh -c 'echo $$ > {scope} && exec runuser -u {user} -- sh /tmp/in-session.sh'"
        )

    def run_as(user, cmd):
        # As `user` with no session at all (an ssh login, a cron job, ...).
        machine.succeed(f"cat > /tmp/run-as.sh <<'EOS'\n{cmd}\nEOS\nchmod 755 /tmp/run-as.sh")
        return machine.execute(f"runuser -u {user} -- sh /tmp/run-as.sh")

    def as_greeter(cmd, stdin=""):
        hub = session_on("tty1", "greeter")["session"]
        return in_session(hub, "greeter", cmd, stdin)

    def alice_to_hub():
        # What a lock keybind does: switch to the login screen's session.
        hub = session_on("tty1", "greeter")["session"]
        status, out = in_session(alice, "alice", f"loginctl activate {hub}")
        assert status == 0, (status, out)

    def wait_hub(timeout=20):
        try:
            machine.wait_until_succeeds("grep -qx tty1 /sys/class/tty/tty0/active", timeout=timeout)
        except Exception:
            print(machine.execute(
                "journalctl -u coel-vt-guard --no-pager | tail -15; "
                "for f in /run/systemd/sessions/*; do echo \"== $f\"; grep -e CLASS -e STATE -e TTY $f; done; "
                "cat /sys/class/tty/tty0/active"
            )[1])
            raise

    def brightness():
        return int(machine.succeed("cat /run/fake-bl/panel/brightness").strip())

    def poke():
        # One key press, as the guard sees it on a real input device. (Only while
        # the login screen is on screen: that is the only time the pipe is read.)
        machine.succeed(
            "timeout 3 sh -c \"printf '\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\1\\0\\36\\0\\1\\0\\0\\0' > /run/fake-input/event0\""
        )

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("greetd.service")
    machine.wait_for_unit("greetd-host-7.service")
    machine.wait_for_unit("greetd-host-8.service")
    machine.wait_for_unit("coel-vt-guard.service")

    with subtest("boot ends on the login screen (VT1), hosts idle behind it"):
        machine.wait_until_succeeds("grep -qx tty1 /sys/class/tty/tty0/active", timeout=30)
        assert session_on("tty1", "greeter"), "no hub greeter on tty1"
        machine.wait_until_succeeds("loginctl list-sessions --json=short | jq -e '.[] | select(.tty==\"tty7\" and .class==\"greeter\")'")
        machine.succeed("coel-hub free-host | grep -qx 7")

    with subtest("wrong password is refused and starts nothing"):
        status, out = as_greeter("coel-hub auth alice --host auto --cmd sleep infinity", '{"response": "nope"}\n{"response": "nope"}')
        assert '"fail"' in out, out
        assert session_on("tty7", "user") is None

    with subtest("login screen to WM: correct password starts a session on a host VT"):
        status, out = as_greeter(
            "coel-hub auth alice --host auto --env XDG_SESSION_DESKTOP=hyprland --cmd sleep infinity",
            '{"response": "secret"}',
        )
        assert status == 0 and '"ok"' in out, out
        started = time.monotonic()
        machine.wait_until_succeeds("loginctl list-sessions --json=short | jq -e '.[] | select(.tty==\"tty7\" and .class==\"user\" and .user==\"alice\")'", timeout=30)
        machine.wait_until_succeeds("grep -qx tty7 /sys/class/tty/tty0/active", timeout=15)
        took = time.monotonic() - started
        print(f"start_session -> session on screen: {took:.1f}s")
        assert took < 3, f"greetd took {took:.1f}s to put the new session on screen"
        machine.succeed("coel-hub free-host | grep -qx 8")  # the next host is the free one

    alice = session_on("tty7", "user")["session"]

    with subtest("WM to login screen"):
        alice_to_hub()
        machine.wait_until_succeeds("grep -qx tty1 /sys/class/tty/tty0/active", timeout=15)

    with subtest("manual switch into the session is bounced back to the login screen"):
        machine.succeed("chvt 7")
        machine.wait_until_succeeds("grep -qx tty1 /sys/class/tty/tty0/active", timeout=15)
        machine.succeed("journalctl -u coel-vt-guard --no-pager | grep -q 'leaving VT 7 (unauthorised switch into a session)'")

    with subtest("a normal user cannot forge a switch authorisation or an unlock grant"):
        for who, run in (
            ("alice, inside her session", lambda c: in_session(alice, "alice", c)),
            ("mallory, no session", lambda c: run_as("mallory", c)),
        ):
            status, _ = run("echo 7 > /run/coel-hub/allow")
            assert status != 0, f"{who} could write a switch token"
            status, _ = run(f"touch /run/coel-hub/unlock/{alice}")
            assert status != 0, f"{who} could grant an unlock"
        machine.fail("test -e /run/coel-hub/allow")
        machine.fail(f"test -e /run/coel-hub/unlock/{alice}")

    with subtest("the hub can grant an unlock, and the session can see it"):
        # What the session's lock screen does: wait for a fresh grant file.
        machine.succeed(
            "cat > /tmp/watch.sh <<'EOS'\n"
            f"until [ -r /run/coel-hub/unlock/{alice} ]; do sleep 0.2; done\n"
            "echo UNLOCK > /tmp/unlock.log\n"
            "EOS"
        )
        machine.succeed("systemd-run --uid=alice --unit=lockwatch --collect sh /tmp/watch.sh")
        machine.sleep(1)
        machine.succeed("systemctl is-active lockwatch.service")
        machine.fail("test -e /tmp/unlock.log")
        status, out = as_greeter(f"coel-hub resume {alice}")
        assert status == 0, out
        machine.wait_until_succeeds("grep -q UNLOCK /tmp/unlock.log", timeout=15)

    with subtest("login screen to existing WM: resume switches to it, no bounce"):
        machine.wait_until_succeeds("grep -qx tty7 /sys/class/tty/tty0/active", timeout=15)
        time.sleep(3)
        assert active_vt() == "tty7", "guard bounced an authorised switch: " + active_vt()

    with subtest("sessions: the login screen sees the live session, with its desktop"):
        status, out = as_greeter("coel-hub sessions")
        listed = json.loads(out)
        mine = [x for x in listed if x["user"] == "alice"]
        assert len(mine) == 1 and mine[0]["tty"] == "tty7" and mine[0]["desktop"] == "hyprland" and mine[0]["active"], listed

    with subtest("lock: the session locks itself, then the login screen takes over"):
        assert active_vt() == "tty7", active_vt()
        status, out = in_session(alice, "alice", f"env XDG_SESSION_ID={alice} coel-hub lock")
        assert status == 0, (status, out)
        machine.wait_until_succeeds("grep -qx tty1 /sys/class/tty/tty0/active", timeout=15)
        machine.succeed("pgrep -f '[l]ock-stub'")  # the lock screen is still up in the background
        machine.succeed(f"test -e /run/user/1000/coel-lock-ready-{alice}")
        status, out = as_greeter("coel-hub sessions")
        assert [x for x in json.loads(out) if x["user"] == "alice" and not x["active"]], out
        # locking again while locked must not start a second lock screen
        before = machine.succeed("pgrep -fc '[l]ock-stub'").strip()
        status, out = in_session(alice, "alice", f"env XDG_SESSION_ID={alice} coel-hub lock")
        assert status == 0, (status, out)
        after = machine.succeed("pgrep -fc '[l]ock-stub'").strip()
        assert before == after, f"a second lock screen was started ({before} -> {after})"

    with subtest("lock without a session id, with the login screen on screen, locks nothing"):
        # A background session's idle timer (no XDG_SESSION_ID, nothing of
        # alice's on screen) must not lock the login screen's own session.
        before = machine.succeed("pgrep -fc '[l]ock-stub'").strip()
        status, out = in_session(alice, "alice", "coel-hub lock")
        assert status == 0, (status, out)
        assert machine.succeed("pgrep -fc '[l]ock-stub'").strip() == before, "locked the wrong session"
        assert active_vt() == "tty1", active_vt()

    with subtest("resume lets the lock go and shows the session"):
        status, out = as_greeter(f"coel-hub resume {alice}")
        assert status == 0, out
        machine.wait_until_succeeds("! pgrep -f '[l]ock-stub'", timeout=15)
        machine.wait_until_succeeds("grep -qx tty7 /sys/class/tty/tty0/active", timeout=15)
        time.sleep(2)
        assert active_vt() == "tty7", active_vt()

    with subtest("hub PAM check (resume path): right and wrong password"):
        # main greetd's socket belongs to the hub greeter; use it as the oracle.
        main_pid = machine.succeed("systemctl show -p MainPID --value greetd.service").strip()
        env = f"GREETD_SOCK=/run/greetd-{main_pid}.sock"
        status, out = as_greeter(f"env {env} coel-hub auth alice", '{"response": "secret"}')
        assert status == 0 and '"ok"' in out, out
        status, out = as_greeter(f"env {env} coel-hub auth alice", '{"response": "wrong"}\n{"response": "wrong"}')
        assert '"fail"' in out, out

    with subtest("WM to login screen, then logout lands on the login screen"):
        alice_to_hub()
        machine.wait_until_succeeds("grep -qx tty1 /sys/class/tty/tty0/active", timeout=15)
        machine.succeed(f"loginctl terminate-session {alice}")
        machine.wait_until_succeeds("! loginctl list-sessions --json=short | jq -e '.[] | select(.tty==\"tty7\" and .class==\"user\")'", timeout=30)
        # greetd re-activates the host VT for its idle greeter; the guard must bounce that too.
        time.sleep(3)
        assert active_vt() == "tty1", "not back on the login screen after logout: " + active_vt()
        machine.succeed("coel-hub free-host | grep -qx 7")

    with subtest("hosts survive repeated logins, logouts and a stray switch into an idle host"):
        # greetd blocks until its VT is on screen; the guard must never take it
        # away before that, or the host is wedged for good.
        for host in ("7", "8", "7", "8"):
            status, out = as_greeter(
                f"coel-hub auth alice --host {host} --cmd sleep infinity",
                '{"response": "secret"}',
            )
            assert status == 0 and '"ok"' in out, (host, out)
            machine.wait_until_succeeds(f"grep -qx tty{host} /sys/class/tty/tty0/active", timeout=20)
            machine.wait_until_succeeds(
                f"loginctl list-sessions --json=short | jq -e '.[] | select(.tty==\"tty{host}\" and .class==\"user\")'",
                timeout=20,
            )
            sid = session_on(f"tty{host}", "user")["session"]
            machine.succeed(f"loginctl terminate-session {sid}")
            machine.wait_until_succeeds(
                f"! loginctl list-sessions --json=short | jq -e '.[] | select(.tty==\"tty{host}\" and .class==\"user\")'",
                timeout=30,
            )
            wait_hub()
        machine.succeed("chvt 8")  # someone pokes an idle host: bounced, but not wedged
        wait_hub()
        status, out = as_greeter(
            "coel-hub auth alice --host 8 --cmd sleep infinity",
            '{"response": "secret"}',
        )
        assert status == 0 and '"ok"' in out, out
        machine.wait_until_succeeds("grep -qx tty8 /sys/class/tty/tty0/active", timeout=20)
        sid = session_on("tty8", "user")["session"]
        machine.succeed(f"loginctl terminate-session {sid}")
        wait_hub(30)

    # ===================== the guest account =====================
    def wait_live(sid):
        # A session shows up in logind before greetd has finished starting its
        # process; wait until it is really on screen before touching it.
        tty = next(x for x in sessions() if x["session"] == sid)["tty"]
        machine.wait_until_succeeds(f"grep -qx {tty} /sys/class/tty/tty0/active", timeout=30)
        time.sleep(1)

    def guest_login():
        status, out = as_greeter(
            "coel-hub auth guest --host auto --env XDG_SESSION_DESKTOP=hyprland --cmd sleep infinity",
            '{"response": ""}',
        )
        assert status == 0 and '"ok"' in out, out
        machine.wait_until_succeeds(
            "loginctl list-sessions --json=short | jq -e '.[] | select(.user==\"guest\" and .class==\"user\")'",
            timeout=30,
        )
        sid = next(x for x in sessions() if x["user"] == "guest" and x["class"] == "user")["session"]
        wait_live(sid)
        return sid

    def guest_logout(sid):
        machine.succeed(f"loginctl terminate-session {sid}")
        machine.wait_until_succeeds(
            "! loginctl list-sessions --json=short | jq -e '.[] | select(.user==\"guest\" and .class==\"user\")'",
            timeout=30,
        )

    with subtest("guest: signs in with no password through the login screen, home is RAM"):
        machine.succeed("test -f /home/guest/.seeded")  # the profile is there
        assert machine.succeed("findmnt -n -o FSTYPE /home/guest").strip() == "tmpfs"
        assert machine.succeed("stat -c %U /home/guest/.config/app/settings").strip() == "guest"
        guest = guest_login()
        wait_hub_vt = machine.succeed("cat /sys/class/tty/tty0/active").strip()
        assert wait_hub_vt in ("tty7", "tty8"), wait_hub_vt

    with subtest("guest: cannot get in at a console, over ssh, or with sudo"):
        # The console login stack must refuse an empty password; greetd must not.
        machine.succeed("test $(grep '^auth' /etc/pam.d/login | grep -c nullok) -eq 0")
        machine.succeed("test $(grep '^auth' /etc/pam.d/greetd | grep -c nullok) -gt 0")
        status, _ = in_session(guest, "guest", "sudo -n true")
        assert status != 0, "guest could sudo"
        status, _ = in_session(guest, "guest", "id -nG | grep -qw wheel")
        assert status != 0, "guest is in wheel"

    with subtest("guest: no Nix builds, no VPN interfaces, no peeking at other homes"):
        status, out = in_session(guest, "guest", "nix --extra-experimental-features nix-command store ping --store daemon")
        assert status != 0, "guest could use the Nix daemon: " + out
        machine.succeed("nix --extra-experimental-features nix-command store ping --store daemon")  # root still can
        status, _ = in_session(guest, "guest", "ls /home/alice")
        assert status != 0, "guest could read another home"
        table = machine.succeed("nft list table inet coel-guest")
        assert "skuid 1100" in table and "gpd0" in table, table

    with subtest("guest: one session per account is enforced by the hub"):
        status, out = as_greeter(
            "coel-hub auth guest --host auto --cmd sleep infinity", '{"response": ""}'
        )
        assert status != 0 and "already signed in" in out, out
        listed = json.loads(as_greeter("coel-hub sessions")[1])
        assert len([x for x in listed if x["user"] == "guest"]) == 1, listed

    with subtest("guest: files made during the session are real, and survive someone else logging in and out"):
        status, out = in_session(
            guest, "guest",
            "echo secret > /home/guest/note.txt; mkdir /home/guest/Downloads; echo x > /home/guest/Downloads/a; echo t > /tmp/guest-tmp-file",
        )
        assert status == 0, out
        # the profile's directories came from read-only store dirs: still writable
        status, out = in_session(guest, "guest", "touch /home/guest/.config/app/new-file && mkdir /home/guest/.config/new-dir")
        assert status == 0, "guest cannot write into the seeded directories: " + out
        # another account logs in and out: this must NOT wipe the guest's home
        status, out = as_greeter("coel-hub auth alice --host auto --cmd sleep infinity", '{"response": "secret"}')
        assert status == 0 and '"ok"' in out, out
        machine.wait_until_succeeds("loginctl list-sessions --json=short | jq -e '.[] | select(.user==\"alice\" and .class==\"user\")'", timeout=30)
        asid = next(x for x in sessions() if x["user"] == "alice" and x["class"] == "user")["session"]
        wait_live(asid)
        machine.succeed(f"loginctl terminate-session {asid}")
        machine.wait_until_succeeds("! loginctl list-sessions --json=short | jq -e '.[] | select(.user==\"alice\" and .class==\"user\")'", timeout=30)
        time.sleep(4)
        machine.succeed("test -f /home/guest/note.txt && test -f /home/guest/Downloads/a")

    with subtest("guest: logging out undoes everything; the profile comes back"):
        guest_logout(guest)
        machine.wait_until_succeeds("! test -e /home/guest/note.txt", timeout=90)  # actually wiped
        machine.wait_until_succeeds("test -e /run/coel-guest/clean", timeout=60)
        machine.wait_until_succeeds("! systemctl is-active coel-guest-reset.service", timeout=60)
        machine.fail("test -e /home/guest/note.txt")
        machine.fail("test -e /home/guest/Downloads")
        machine.fail("test -e /tmp/guest-tmp-file")
        machine.succeed("test -f /home/guest/.seeded")  # profile put back
        machine.fail("test -e /home/guest/.config/app/new-file")  # ... and only the profile
        assert machine.succeed("stat -c %U /home/guest/.seeded").strip() == "guest"
        assert machine.succeed("stat -c '%U %a' /home/guest").strip() == "guest 700"

    with subtest("guest: the next guest starts clean, even straight after a logout"):
        guest = guest_login()
        machine.fail("test -e /home/guest/note.txt")
        machine.succeed("test -f /home/guest/.seeded")
        status, out = in_session(guest, "guest", "touch /home/guest/.config/app/again")
        assert status == 0, "seeded directories not writable after a wipe: " + out
        guest_logout(guest)
        guest = guest_login()  # immediately: the hub waits for the wipe to finish
        machine.fail("test -e /home/guest/note.txt")
        machine.succeed("test -f /home/guest/.seeded")
        guest_logout(guest)
        machine.wait_until_succeeds("! systemctl is-active coel-guest-reset.service", timeout=60)

    # ===================== login-screen idle: screen off, suspend =====================
    with subtest("idle login screen: the backlight goes dark, any input brings it back"):
        wait_hub(30)
        poke()
        time.sleep(1)
        assert brightness() == 80, brightness()
        machine.wait_until_succeeds("test $(cat /run/fake-bl/panel/brightness) -eq 0", timeout=20)
        poke()
        machine.wait_until_succeeds("test $(cat /run/fake-bl/panel/brightness) -eq 80", timeout=10)

    with subtest("leaving the login screen restores the backlight; a session on screen is never blanked"):
        poke()
        machine.wait_until_succeeds("test $(cat /run/fake-bl/panel/brightness) -eq 0", timeout=20)
        status, out = as_greeter(
            "coel-hub auth alice --host auto --env XDG_SESSION_DESKTOP=hyprland --cmd sleep infinity",
            '{"response": "secret"}',
        )
        assert status == 0 and '"ok"' in out, out
        machine.wait_until_succeeds("test $(cat /run/fake-bl/panel/brightness) -eq 80", timeout=15)
        asid = next(x for x in sessions() if x["user"] == "alice" and x["class"] == "user")["session"]
        wait_live(asid)
        time.sleep(10)  # well past the 6s blank time, with the session on screen
        assert brightness() == 80, "the screen was blanked with a session on it"
        machine.succeed("rm -f /run/suspend-called")
        time.sleep(30)  # and past the 24s suspend time
        machine.fail("test -e /run/suspend-called")

    with subtest("the session's last-resort suspend only fires for the session on screen"):
        status, out = in_session(
            asid, "alice",
            f"env XDG_SESSION_ID={asid} COEL_SUSPEND_CMD='touch /tmp/fallback-called' coel-hub suspend-fallback",
        )
        assert status == 0, out
        machine.succeed("test -e /tmp/fallback-called")  # it is on screen: suspends
        machine.succeed("rm -f /tmp/fallback-called")
        hub_sid = session_on("tty1", "greeter")["session"]
        status, out = in_session(asid, "alice", f"loginctl activate {hub_sid}")
        assert status == 0, out
        wait_hub(15)
        status, out = in_session(
            asid, "alice",
            f"env XDG_SESSION_ID={asid} COEL_SUSPEND_CMD='touch /tmp/fallback-called' coel-hub suspend-fallback",
        )
        assert status == 0, out
        machine.fail("test -e /tmp/fallback-called")  # the login screen is on screen: leaves it alone
        machine.succeed(f"loginctl terminate-session {asid}")
        machine.wait_until_succeeds("! loginctl list-sessions --json=short | jq -e '.[] | select(.user==\"alice\" and .class==\"user\")'", timeout=40)
        wait_hub(30)

    with subtest("idle login screen: suspends after the long idle, and input puts that off"):
        machine.succeed("rm -f /run/suspend-called")
        time.sleep(3)
        poke()
        time.sleep(14)  # 14s idle, suspend is at 24s
        machine.fail("test -e /run/suspend-called")
        poke()          # someone is here: the clock starts over
        time.sleep(14)
        machine.fail("test -e /run/suspend-called")
        machine.wait_until_succeeds("test -e /run/suspend-called", timeout=40)

    with subtest("inhibitors: \"keep awake\" (block idle) stops dimming and suspending; a sleep-only block only stops suspending; a delay inhibitor counts for nothing"):
        def inhibitor(what, mode):
            # logind's own state-file format: one KEY=VALUE per line
            machine.succeed(f"printf 'WHAT=%s\\nMODE=%s\\nWHO=%s\\n' {what} {mode} keepawake > /run/fake-inhibit/1")

        wait_hub(30)
        # 1. block on idle (the launcher's keep-awake toggle): nothing happens at all
        inhibitor("sleep:idle", "block")
        machine.succeed("rm -f /run/suspend-called")
        poke()
        time.sleep(12)   # past the 6s dim time
        assert brightness() == 80, "dimmed while something asked for the machine to stay awake"
        time.sleep(26)   # past the 24s suspend time
        machine.fail("test -e /run/suspend-called")
        # ... and it carries on as normal once it is released
        machine.succeed("rm /run/fake-inhibit/1")
        machine.wait_until_succeeds("test $(cat /run/fake-bl/panel/brightness) -eq 0", timeout=25)
        machine.wait_until_succeeds("test -e /run/suspend-called", timeout=45)

        # 2. block on sleep only: may dim, must not suspend
        machine.succeed("rm -f /run/suspend-called")
        poke()
        inhibitor("sleep", "block")
        machine.wait_until_succeeds("test $(cat /run/fake-bl/panel/brightness) -eq 0", timeout=25)
        time.sleep(30)
        machine.fail("test -e /run/suspend-called")
        machine.succeed("rm /run/fake-inhibit/1")
        machine.wait_until_succeeds("test -e /run/suspend-called", timeout=45)

        # 3. delay inhibitors (NetworkManager, UPower, ...) only ask for a moment: ignored
        machine.succeed("rm -f /run/suspend-called")
        poke()
        inhibitor("sleep:idle", "delay")
        machine.wait_until_succeeds("test $(cat /run/fake-bl/panel/brightness) -eq 0", timeout=25)
        machine.wait_until_succeeds("test -e /run/suspend-called", timeout=45)
        machine.succeed("rm /run/fake-inhibit/1")
        poke()

    with subtest("holds: the login screen is told what keeps the machine awake, and whose it is"):
        uid = machine.succeed("id -u alice").strip()
        machine.succeed(
            f"printf 'UID=%s\\nPID=1\\nWHAT=%s\\nMODE=%s\\nWHO=%s\\nWHY=%s\\n' {uid} sleep:idle block 'CoelOS launcher' 'keep awake' > /run/fake-inhibit/10"
        )
        machine.succeed(f"printf 'UID=%s\\nWHAT=%s\\nMODE=%s\\nWHO=%s\\n' {uid} sleep delay NetworkManager > /run/fake-inhibit/11")
        machine.succeed(f"printf 'UID=%s\\nWHAT=%s\\nMODE=%s\\nWHO=%s\\n' {uid} handle-power-key block Hyprland > /run/fake-inhibit/12")
        status, out = as_greeter("env COEL_INHIBIT_DIR=/run/fake-inhibit coel-hub holds")
        assert status == 0, out
        got = json.loads(out)
        # only the block on idle/sleep counts; a delay inhibitor and a power-key block do not
        assert got == [{"user": "alice", "who": "CoelOS launcher", "why": "keep awake", "blocks": ["idle", "sleep"]}], got
        machine.succeed("rm -f /run/fake-inhibit/10 /run/fake-inhibit/11 /run/fake-inhibit/12")
        status, out = as_greeter("env COEL_INHIBIT_DIR=/run/fake-inhibit coel-hub holds")
        assert json.loads(out) == [], out

    with subtest("plain consoles stay reachable (recovery)"):
        # Let the last logout's host restart settle first: greetd takes the screen
        # when it brings an idle host back, and the guard then returns it to the
        # login screen (so a console you sit on during that moment is pulled back).
        wait_hub(30)
        time.sleep(5)
        machine.succeed("chvt 3")
        time.sleep(2)
        assert active_vt() == "tty3", active_vt()
  '';
}

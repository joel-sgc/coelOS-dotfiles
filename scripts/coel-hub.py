"""coel-hub: client side of the session hub (modules/session-hub.nix).

The login screen lives on VT1 and never starts a session itself. Sessions are
hosted by extra greetd instances on other VTs ("hosts"). This is the small
client the login screen uses:

  auth USER [--host VT|auto --cmd CMD... --env KEY=VAL...]
      Run the PAM conversation for USER (password, then fingerprint, whatever
      the greetd PAM stack asks for). Without --host it only CHECKS the
      credentials (on the hub's own greetd, via $GREETD_SOCK) and starts
      nothing. With --host it authenticates against that host greetd and then
      starts CMD there as USER, which switches to the host's VT.
      Talks JSON lines on stdio so a UI can drive it:
        out: {"event":"prompt","kind":"secret"|"visible","text":"..."}
             {"event":"info"|"error","text":"..."}
             {"event":"ok"} | {"event":"fail","text":"..."}
        in:  {"response":"..."}            (one per prompt)

  One session per account: `auth --host` refuses to start a second session for
  a user who already has one (the login screen turns that into "resume").

  resume SESSION
      Let SESSION's lock screen go (see grant_unlock) and switch to its VT.
      Call only after `auth USER` said ok.

  hub
      Switch to the login screen.

  lock
      Lock the calling user's session, then go to the login screen. This is
      what Super+L, the power menu and the idle timer run. The session's lock
      screen is engaged first (and only then is the VT left), so a session in
      the background is always locked. The login screen is shown only if this
      session is the one on screen, so an idle session in the background never
      pulls you away from the one you are using.

  holds
      JSON list of what is keeping the machine awake, for the login screen:
      [{"user","who","why","blocks"}]. These are logind's `block` inhibitors on
      idle or sleep (the launcher's "keep awake" toggle, a video call, ...);
      the login screen neither dims nor suspends while one exists.

  suspend-fallback
      Suspend the machine, but only if this session is the one on screen. Used by
      the session's idle timer as a last resort (a session that is locked in
      place because the login screen is not running): with the login screen or
      another session on screen their own idle handling decides, so a session in
      the background can never suspend the machine under someone else.

  sessions
      JSON list of the live sessions hosted on the session VTs, for the login
      screen: [{"id","user","tty","desktop","active"}].

  free-host
      Print the VT of an idle session host.

  wait-host VT
      Used by the host's own unit at boot: return once the host's idle greeter
      is up AND the screen has moved off its VT. Hosts start one at a time
      because greetd switches to its VT and then blocks until it is on screen;
      starting them together makes their switches race, and the one that loses
      waits for a VT that never comes (see modules/session-hub.nix).

The VT guard (coel-vt-guard) sends every VT switch that did not come through
here straight back to the hub; a switch is "authorised" by the token file this
writes just before it happens. The token directory is writable only by the
greeter user, so programs running as a normal user cannot forge one.
"""

import argparse
import json
import os
import pwd
import select
import shlex
import socket
import struct
import subprocess
import sys
import time

TOKEN_DIR = os.environ.get("COEL_HUB_DIR", "/run/coel-hub")
HOST_VTS = os.environ.get("COEL_HOST_VTS", "7 8").split()
HUB_VT = 1


def emit(**event):
    print(json.dumps(event), flush=True)


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def sessions():
    out = run("loginctl", "list-sessions", "--json=short").stdout
    try:
        return json.loads(out)
    except ValueError:
        return []


def authorise_switch(vt):
    """Tell the VT guard the coming switch to `vt` is legitimate."""
    os.makedirs(TOKEN_DIR, exist_ok=True)
    tmp = os.path.join(TOKEN_DIR, ".allow.tmp")
    with open(tmp, "w") as f:
        f.write(f"{vt}\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, os.path.join(TOKEN_DIR, "allow"))


def release_host_greeter(vt):
    """Let greetd start the session now.

    After start_session greetd waits for the host's greeter program to exit and
    only kills it after ~5 s. The idle placeholder never exits by itself, so
    every login would sit through that timeout. We run as the greeter user, so
    we may end its processes: everything in the host's greeter session scope."""
    sid = None
    try:
        for name in os.listdir("/run/systemd/sessions"):
            if not name.isdigit():
                continue
            with open(os.path.join("/run/systemd/sessions", name)) as f:
                fields = dict(line.rstrip("\n").partition("=")[::2] for line in f)
            if (fields.get("TTY") == f"tty{vt}" and fields.get("CLASS") == "greeter"
                    and fields.get("UID") == str(os.getuid())):
                sid = name
        if sid is None:
            return
        procs = f"/sys/fs/cgroup/user.slice/user-{os.getuid()}.slice/session-{sid}.scope/cgroup.procs"
        with open(procs) as f:
            pids = [int(p) for p in f.read().split()]
    except (OSError, ValueError):
        return
    for pid in pids:
        if pid != os.getpid():
            try:
                os.kill(pid, 15)
            except OSError:
                pass


def live_sessions_of(user):
    """Sessions of `user` that are up on the session VTs: [(id, tty)]."""
    found = []
    try:
        names = os.listdir("/run/systemd/sessions")
    except OSError:
        return found
    for name in names:
        if not name.isdigit():
            continue
        try:
            with open(os.path.join("/run/systemd/sessions", name)) as f:
                fields = dict(line.rstrip("\n").partition("=")[::2] for line in f)
        except OSError:
            continue
        tty = fields.get("TTY", "")
        if (
            fields.get("USER") == user
            and fields.get("CLASS") == "user"
            and fields.get("STATE") in ("active", "online")
            and tty.startswith("tty")
            and tty[3:] in HOST_VTS
        ):
            found.append((name, tty))
    return found


def wait_for_guest_reset(timeout=40):
    """A throwaway account is wiped after logout (modules/guest.nix); starting
    a session while that is running would see a half-deleted home."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        state = run("systemctl", "is-active", "coel-guest-reset.service").stdout.strip()
        if state not in ("activating", "active", "deactivating"):
            return
        time.sleep(0.3)


def host_is_free(vt):
    unit = f"greetd-host-{vt}.service"
    if run("systemctl", "is-active", "--quiet", unit).returncode != 0:
        return False
    return not any(
        s.get("class") == "user" and s.get("tty") == f"tty{vt}" for s in sessions()
    )


def free_host():
    for vt in HOST_VTS:
        if host_is_free(vt):
            return vt
    return None


def host_socket(vt):
    unit = f"greetd-host-{vt}.service"
    pid = run("systemctl", "show", "-p", "MainPID", "--value", unit).stdout.strip()
    if not pid or pid == "0":
        raise RuntimeError(f"host on VT {vt} is not running")
    return f"/run/greetd-{pid}.sock"


# ---- greetd wire protocol: u32 length (native byte order) + JSON ----------

def read_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("greetd closed the connection")
        buf += chunk
    return buf


def send(sock, message):
    body = json.dumps(message).encode()
    sock.sendall(struct.pack("=I", len(body)) + body)


def receive(sock):
    (length,) = struct.unpack("=I", read_exact(sock, 4))
    return json.loads(read_exact(sock, length))


def read_reply():
    line = sys.stdin.readline()
    if not line:
        raise EOFError("no reply")
    return json.loads(line).get("response")


def converse(sock, user):
    """Drive PAM through greetd until success or failure."""
    send(sock, {"type": "create_session", "username": user})
    while True:
        reply = receive(sock)
        kind = reply.get("type")
        if kind == "success":
            return True, ""
        if kind == "error":
            # greetd leaves no session behind on error.
            return False, reply.get("description", "authentication failed")
        if kind == "auth_message":
            style = reply.get("auth_message_type")
            text = reply.get("auth_message", "")
            if style in ("info", "error"):
                emit(event=style, text=text)
                send(sock, {"type": "post_auth_message_response", "response": None})
            else:
                emit(event="prompt", kind=style, text=text)
                send(sock, {"type": "post_auth_message_response", "response": read_reply()})


def activate_new_session(user, vt, timeout=5.0):
    """Put the session that just started on `vt` on screen.

    greetd registers it with logind a moment after start_session (once the
    host's placeholder greeter has gone), so wait for it to show up."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        for sid, tty in live_sessions_of(user):
            if tty == f"tty{vt}":
                run("loginctl", "activate", sid)
                return True
        time.sleep(0.05)
    print(f"coel-hub: no session of {user} appeared on tty{vt}", file=sys.stderr)
    return False


def cmd_auth(args):
    starting = args.host is not None
    if starting:
        mine = live_sessions_of(args.user)
        if mine:
            emit(event="fail", text=f"already signed in on {mine[0][1]}: resume that session")
            return 1
        if args.user == os.environ.get("COEL_GUEST_USER", "guest"):
            wait_for_guest_reset()
        vt = free_host() if args.host == "auto" else args.host
        if vt is None:
            emit(event="fail", text="no free session slot")
            return 1
        path = host_socket(vt)
    else:
        path = os.environ.get("GREETD_SOCK")
        if not path:
            emit(event="fail", text="GREETD_SOCK is not set")
            return 1

    sock = socket.socket(socket.AF_UNIX)
    sock.connect(path)
    finished = False
    try:
        ok, why = converse(sock, args.user)
        if not ok:
            emit(event="fail", text=why)
            return 1
        if not starting:
            send(sock, {"type": "cancel_session"})
            receive(sock)
            finished = True
            emit(event="ok")
            return 0
        # Authenticated: give the greeter a moment to settle into its "starting"
        # picture before the switch, since that picture stays on screen (frozen)
        # until the compositor draws. It answers with any line; without an
        # answer (an older greeter, a script, the VM test) we go on after 0.8 s.
        emit(event="authenticated")
        try:
            ready, _, _ = select.select([sys.stdin], [], [], 0.8)
            if ready:
                sys.stdin.readline()
        except (OSError, ValueError):
            pass
        # Hosts don't switch the screen themselves (switch = false, see
        # modules/session-hub.nix): once the session exists, we activate it,
        # like resume does. The guard lets this switch through.
        authorise_switch(vt)
        send(sock, {"type": "start_session", "cmd": args.cmd, "env": args.env})
        reply = receive(sock)
        if reply.get("type") != "success":
            emit(event="fail", text=reply.get("description", "could not start the session"))
            return 1
        release_host_greeter(vt)
        activate_new_session(args.user, vt)
        finished = True
        emit(event="ok", vt=int(vt))
        return 0
    finally:
        if not finished:
            # greetd keeps a half-configured session around after a failed or
            # abandoned login and refuses the next one ("a session is already
            # being configured") until it is cancelled.
            try:
                send(sock, {"type": "cancel_session"})
                receive(sock)
            except (OSError, ValueError):
                pass
        sock.close()


def session_vt(session_id):
    for s in sessions():
        if s.get("session") == session_id:
            tty = s.get("tty") or ""
            if tty.startswith("tty"):
                return int(tty[3:])
    return None


def grant_unlock(session_id):
    """Tell session `session_id`'s lock screen it may let go.

    The lock screen waits for this file to appear and be NEWER than the
    moment it confirmed its own lock, so a leftover grant can never unlock a
    later lock; the file is also removed a few seconds after use.
    /run/coel-hub/unlock is writable only
    by the greeter user, so programs running as a normal user -- including ones
    inside the locked session itself -- can read it but cannot create it. (logind's own
    unlock-session is no use here: it lets a session's owner unlock their own
    session, so anything running in the session could drop its lock.)
    """
    directory = os.path.join(TOKEN_DIR, "unlock")
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, session_id)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"{int(time.time())}\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    # Tidy up once the lock screen has had ample time to notice it.
    subprocess.Popen(
        ["sh", "-c", 'sleep 6; rm -f "$0"', path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def cmd_resume(args):
    vt = session_vt(args.session)
    if vt is None:
        print(f"no such session: {args.session}", file=sys.stderr)
        return 1
    grant_unlock(args.session)
    authorise_switch(vt)
    return run("loginctl", "activate", args.session).returncode


def active_session():
    return run("loginctl", "show-seat", "seat0", "-p", "ActiveSession", "--value").stdout.strip()


def own_session():
    """The session the caller belongs to. Keybinds inherit XDG_SESSION_ID;
    services such as hypridle may not. For those the session on screen is the
    best guess -- but only if it is a regular session of the calling user. If
    the login screen (or someone else's session) is on screen, the caller is an
    idle background session we cannot identify: do nothing rather than lock the
    wrong thing."""
    sid = os.environ.get("XDG_SESSION_ID")
    if sid:
        return sid
    sid = active_session()
    if not sid:
        return None
    shown = run("loginctl", "show-session", sid, "-p", "Class", "-p", "Name").stdout
    props = dict(line.partition("=")[::2] for line in shown.splitlines())
    if props.get("Class") == "user" and props.get("Name") == pwd.getpwuid(os.getuid()).pw_name:
        return sid
    return None


def lock_process_running(sid):
    """Is a lock screen for session `sid` already up? Ours carry COEL_LOCK_FOR."""
    needle = f"COEL_LOCK_FOR={sid}".encode()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/environ", "rb") as f:
                if needle in f.read().split(b"\0"):
                    return True
        except OSError:
            continue
    return False


def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


def lock_ready_marker(sid):
    return os.path.join(runtime_dir(), f"coel-lock-ready-{sid}")


def cmd_lock(_args):
    sid = own_session()
    if not sid:
        # Nothing of ours is on screen to lock. Not an error: a background
        # session's idle timer firing while another session (or the login
        # screen) is shown lands here.
        return 0
    ready = lock_ready_marker(sid)

    if not lock_process_running(sid):
        # The lock screen drops this marker once the compositor has CONFIRMED
        # the lock (Lock.qml, WlSessionLock.secure). Leaving the VT any
        # earlier would leave the session unlocked in the background.
        try:
            os.unlink(ready)
        except OSError:
            pass
        command = os.environ.get(
            "COEL_LOCK_CMD", "quickshell -p ~/.nixos/home/quickshell/lock-real-shell.qml"
        )
        subprocess.Popen(
            ["sh", "-c", command],
            env={
                **os.environ,
                "XDG_SESSION_ID": sid,
                "XDG_RUNTIME_DIR": runtime_dir(),
                "COEL_LOCK_FOR": sid,
            },
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.time() + 4
        while time.time() < deadline and not os.path.exists(ready):
            time.sleep(0.05)
        if not os.path.exists(ready):
            run("notify-send", "-u", "critical", "Lock", "The screen lock did not engage; staying here.")
            return 1

    if sid == active_session():
        # Best effort: if the login screen is not up the session simply stays
        # locked in place, with its own lock screen.
        cmd_hub(None)
    return 0


def cmd_holds(_args):
    directory = os.environ.get("COEL_INHIBIT_DIR", "/run/systemd/inhibit")
    found = []
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        names = []
    for name in names:
        if not name.isdigit():
            continue
        try:
            with open(os.path.join(directory, name)) as f:
                fields = dict(line.rstrip("\n").partition("=")[::2] for line in f)
        except OSError:
            continue
        if fields.get("MODE") != "block":
            continue
        blocks = sorted(set(fields.get("WHAT", "").split(":")) & {"idle", "sleep"})
        if not blocks:
            continue
        try:
            user = pwd.getpwuid(int(fields.get("UID", ""))).pw_name
        except (KeyError, ValueError):
            user = fields.get("UID", "?")
        found.append(
            {
                "user": user,
                "who": fields.get("WHO", "?").strip('"'),
                "why": fields.get("WHY", "").strip('"'),
                "blocks": blocks,
            }
        )
    print(json.dumps(found))
    return 0


def cmd_suspend_fallback(_args):
    sid = own_session()
    if sid and sid == active_session():
        subprocess.run(
            shlex.split(os.environ.get("COEL_SUSPEND_CMD", "systemctl suspend")), check=False
        )
    return 0


def cmd_sessions(_args):
    found = []
    for s in sessions():
        tty = s.get("tty") or ""
        if s.get("class") != "user" or s.get("seat") != "seat0":
            continue
        if not tty.startswith("tty") or tty[3:] not in HOST_VTS:
            continue
        props = {}
        shown = run("loginctl", "show-session", s["session"], "-p", "State", "-p", "Desktop").stdout
        for line in shown.splitlines():
            key, _, value = line.partition("=")
            props[key] = value
        state = props.get("State", "")
        if state not in ("active", "online"):
            continue  # closing sessions are not offered
        found.append(
            {
                "id": s["session"],
                "user": s["user"],
                "tty": tty,
                "desktop": props.get("Desktop", ""),
                "active": state == "active",
            }
        )
    print(json.dumps(found))
    return 0


def cmd_wait_host(args):
    vt = args.vt
    deadline = time.time() + 25
    while time.time() < deadline:
        greeter_up = False
        try:
            for name in os.listdir("/run/systemd/sessions"):
                if not name.isdigit():
                    continue
                with open(os.path.join("/run/systemd/sessions", name)) as f:
                    fields = dict(line.rstrip("\n").partition("=")[::2] for line in f)
                if (
                    fields.get("CLASS") == "greeter"
                    and fields.get("TTY") == f"tty{vt}"
                    and fields.get("STATE") in ("active", "online")
                ):
                    greeter_up = True
            with open("/sys/class/tty/tty0/active") as f:
                on_screen = f.read().strip()
        except OSError:
            greeter_up, on_screen = False, ""
        if greeter_up and on_screen != f"tty{vt}":
            return 0
        time.sleep(0.1)
    return 0  # never hold up boot over this


def cmd_hub(_args):
    for s in sessions():
        if s.get("class") == "greeter" and s.get("tty") == f"tty{HUB_VT}":
            return run("loginctl", "activate", s["session"]).returncode
    print("the login screen is not running", file=sys.stderr)
    return 1


def cmd_free_host(_args):
    vt = free_host()
    if vt is None:
        return 1
    print(vt)
    return 0


def main():
    parser = argparse.ArgumentParser(prog="coel-hub")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("auth")
    p.add_argument("user")
    p.add_argument("--host")
    p.add_argument("--env", action="append", default=[])
    p.add_argument("--cmd", nargs=argparse.REMAINDER, default=[])
    p.set_defaults(func=cmd_auth)

    p = sub.add_parser("resume")
    p.add_argument("session")
    p.set_defaults(func=cmd_resume)

    sub.add_parser("hub").set_defaults(func=cmd_hub)
    sub.add_parser("lock").set_defaults(func=cmd_lock)
    sub.add_parser("sessions").set_defaults(func=cmd_sessions)
    sub.add_parser("holds").set_defaults(func=cmd_holds)
    sub.add_parser("suspend-fallback").set_defaults(func=cmd_suspend_fallback)
    sub.add_parser("free-host").set_defaults(func=cmd_free_host)
    p = sub.add_parser("wait-host")
    p.add_argument("vt")
    p.set_defaults(func=cmd_wait_host)

    args = parser.parse_args()
    if args.command == "auth" and args.host and not args.cmd:
        parser.error("--host needs --cmd")
    try:
        return args.func(args)
    except (OSError, RuntimeError, EOFError, ValueError) as err:
        emit(event="fail", text=str(err))
        return 1


if __name__ == "__main__":
    sys.exit(main())

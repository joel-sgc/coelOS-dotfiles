"""coel-vt-guard: only the login screen may bring a session to the foreground.

Sessions live on their own VTs. If something switches to one of them
(Ctrl+Alt+F7, a stray chvt, greetd restarting an idle host after a logout)
without the login screen having authorised it, this puts the screen straight
back on the login screen (VT1). A switch into a live session is bounced
within a few milliseconds, so it shows as a brief black flash and nothing of the
session is visible; one into an idle host (nothing on screen) is given a
moment first, see main().

How a switch is authorised: coel-hub writes the target VT number into
/run/coel-hub/allow just before it happens (the directory is writable only by
the greeter user). A token is valid once, and for a few seconds.

Only the session VTs are guarded. The plain consoles (VT2-6) stay reachable,
so there is always a way to a shell if the login screen ever breaks.

The VT is watched through /sys/class/tty/tty0/active, which the kernel
signals on every change -- no polling.

The login screen also lives or dies by idleness, and this daemon owns that too
(it is root, always running, and knows when the login screen is on screen):
  - after COEL_HUB_BLANK_AFTER seconds without input at the login screen the
    laptop backlight goes to 0 (the greeter runs in a kiosk compositor with no
    way to switch a screen off); any input, or leaving the login screen, brings
    it back;
  - after COEL_HUB_SUSPEND_AFTER seconds the machine suspends.
Block inhibitors are honoured the way hypridle honours them: one that covers
`idle` (the launcher's "keep awake" toggle, systemd-inhibit --what=idle ...)
means someone wants the machine awake, so the login screen neither dims nor
suspends; one that covers only `sleep` still lets it dim but holds the suspend.
(The backlight can only go to the panel's MINIMUM: the amdgpu driver rescales
brightness 0 to its lowest level and ignores bl_power, so "dark" here means
"as dim as this driver allows"; suspend is what really turns the panel off.)
Input is watched on the raw input devices, and only while the login screen is
on screen; events are only COUNTED -- nothing of what is typed is read, kept
or logged. The saved brightness lives in a file under /run so it is put back
after a crash, a restart or `--restore` (the service runs that on stop): a
dead daemon must never leave the screen dark.
"""

import fcntl
import glob
import json
import os
import re
import select
import shlex
import signal
import struct
import subprocess
import sys
import time

ACTIVE = "/sys/class/tty/tty0/active"
TOKEN = "/run/coel-hub/allow"
TOKEN_TTL = 10.0  # seconds
# An idle host VT shows nothing, so leaving it can wait this long. See main().
IDLE_GRACE = 0.8
SESSION_START_WINDOW = 20.0  # how long the hub's session start may take to show up
RECHECK_LIVE = 2.0           # how often a live session's presence is re-checked
HUB_VT = int(os.environ.get("COEL_HUB_VT", "1"))
GUARDED = {int(v) for v in os.environ.get("COEL_GUARDED_VTS", "7 8").split()}

# Login-screen idle handling (0 disables a step). The *_DIR/_CMD ones are test hooks.
HUB_BLANK_AFTER = float(os.environ.get("COEL_HUB_BLANK_AFTER", "120"))
HUB_SUSPEND_AFTER = float(os.environ.get("COEL_HUB_SUSPEND_AFTER", "600"))
SUSPEND_CMD = shlex.split(os.environ.get("COEL_SUSPEND_CMD", "systemctl suspend"))
BACKLIGHT_DIR = os.environ.get("COEL_BL_DIR", "/sys/class/backlight")
INPUT_DIR = os.environ.get("COEL_INPUT_DIR")
STATE_FILE = os.path.join(
    os.environ.get("RUNTIME_DIRECTORY", "/run/coel-vt-guard"), "saved-brightness.json"
)
INPUT_RESCAN = 30.0     # seconds between looks for newly plugged input devices
SUSPEND_RETRY = 60.0    # seconds before trying to suspend again
SUSPEND_BACKOFF = 300.0 # ... after a refusal (an inhibitor, usually)
INHIBIT_RECHECK = 15.0  # while something holds the machine awake: how soon to look again
INHIBIT_DIR = os.environ.get("COEL_INHIBIT_DIR", "/run/systemd/inhibit")
EV_SYN, EV_MSC = 0, 4   # input events that are not "someone did something"
EV_RECORD = struct.Struct("llHHi")

VT_ACTIVATE = 0x5606


def log(message):
    print(message, file=sys.stderr, flush=True)


def consume_token(vt):
    """True if the hub authorised a switch to `vt`; the token is used up."""
    try:
        age = time.time() - os.stat(TOKEN).st_mtime
        with open(TOKEN) as f:
            wanted = f.read().strip()
    except OSError:
        return False
    if age > TOKEN_TTL or wanted != str(vt):
        return False
    try:
        os.unlink(TOKEN)
    except OSError:
        pass
    return True


SESSIONS = "/run/systemd/sessions"


def scan_vt(vt):
    """What logind says is on this VT: (a live user session?, greeter session ids).

    Reads logind's own state files, so it costs nothing and can be asked often.
    Only sessions that are still up count: a session that is "closing" shows
    nothing. An idle host runs a greeter session; when a session ends greetd
    starts a NEW one, which is how an ended session is told apart from one that
    has not appeared yet.
    """
    live = False
    greeters = set()
    try:
        names = os.listdir(SESSIONS)
    except OSError:
        return True, greeters  # in doubt, assume a session: bounce rather than show it
    for name in names:
        if not name.isdigit():
            continue
        try:
            with open(os.path.join(SESSIONS, name)) as f:
                fields = dict(line.rstrip("\n").partition("=")[::2] for line in f)
        except OSError:
            continue
        if fields.get("TTY") != f"tty{vt}" or fields.get("STATE") not in ("active", "online"):
            continue
        if fields.get("CLASS") == "user":
            live = True
        elif fields.get("CLASS") == "greeter":
            greeters.add(name)
    return live, greeters


def go_to_hub():
    # Request the switch and move on; do NOT wait for it (VT_WAITACTIVE). The
    # wait only returns while VT1 is on screen, so if anything switched away
    # again meanwhile -- the hub starting a session, say -- it would block this
    # daemon for good. The main loop re-reads the active VT anyway.
    fd = os.open("/dev/tty0", os.O_RDWR)
    try:
        fcntl.ioctl(fd, VT_ACTIVATE, HUB_VT)
    finally:
        os.close(fd)


def bounce(vt, why):
    log(f"guard: leaving VT {vt} ({why}), back to the login screen")
    try:
        go_to_hub()
    except OSError as err:
        log(f"guard: could not switch: {err}")
        return
    # The switch is asynchronous: wait for it to land, or the loop would see
    # the same VT again and re-issue it dozens of times a second.
    deadline = time.monotonic() + 1.5
    while time.monotonic() < deadline:
        if read_text(ACTIVE) != f"tty{vt}":
            return
        time.sleep(0.05)


def read_text(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def write_text(path, value):
    try:
        with open(path, "w") as f:
            f.write(str(value))
        return True
    except OSError as err:
        log(f"guard: cannot write {path}: {err}")
        return False


def load_saved():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def blank_backlights():
    """Backlight to 0, remembering what it was (in a file, so a crash can undo it)."""
    saved = load_saved()
    for bl in sorted(glob.glob(os.path.join(BACKLIGHT_DIR, "*"))):
        raw = read_text(os.path.join(bl, "brightness"))
        if raw is None or not raw.isdigit():
            continue
        if int(raw) > 0 and bl not in saved:
            saved[bl] = int(raw)
        write_text(os.path.join(bl, "brightness"), 0)
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(saved, f)


def restore_backlights():
    saved = load_saved()
    for bl, value in saved.items():
        top = read_text(os.path.join(bl, "max_brightness"))
        ceiling = int(top) if top and top.isdigit() else int(value)
        write_text(os.path.join(bl, "brightness"), max(1, min(int(value), ceiling)))
    if saved:
        try:
            os.unlink(STATE_FILE)
        except OSError:
            pass


# Devices that only ever report switches/jacks never count as "someone is here";
# capability bits do that for most (a lid switch has no keys/axes). Anything that
# can chatter without a person is listed by name.
NOT_A_PERSON = re.compile(r"accelerometer|hda |hd-audio|lid switch", re.I)
KEY_REL_ABS = (1 << 1) | (1 << 2) | (1 << 3)


def input_devices():
    if INPUT_DIR:
        return sorted(glob.glob(os.path.join(INPUT_DIR, "event*")))
    found = []
    for path in sorted(glob.glob("/dev/input/event*")):
        node = os.path.basename(path)
        name = read_text(f"/sys/class/input/{node}/device/name") or ""
        caps = read_text(f"/sys/class/input/{node}/device/capabilities/ev")
        if NOT_A_PERSON.search(name) or not caps:
            continue
        try:
            if int(caps, 16) & KEY_REL_ABS:
                found.append(path)
        except ValueError:
            continue
    return found


def blocking_inhibitors():
    """(who blocks idle, who blocks sleep): logind's inhibitors of mode `block`.

    Read from logind's own state files; `delay` inhibitors (NetworkManager,
    UPower, ...) only ask for a moment before sleeping and do not count.
    """
    idle, sleep = [], []
    try:
        names = os.listdir(INHIBIT_DIR)
    except OSError:
        return idle, sleep
    for name in names:
        if not name.isdigit():
            continue
        try:
            with open(os.path.join(INHIBIT_DIR, name)) as f:
                fields = dict(line.rstrip("\n").partition("=")[::2] for line in f)
        except OSError:
            continue
        if fields.get("MODE") != "block":
            continue
        what = set(fields.get("WHAT", "").split(":"))
        who = fields.get("WHO", "?").strip('"')
        if "idle" in what:
            idle.append(who)
        if "sleep" in what:
            sleep.append(who)
    return idle, sleep


class HubIdle:
    """Blank and suspend while the login screen sits unused."""

    def __init__(self, watcher):
        self.watcher = watcher
        self.active = False
        self.fds = {}  # fd -> path
        self.idle_since = 0.0
        self.blanked = False
        self.next_suspend = 0.0
        self.last_scan = 0.0
        self.skew = 0.0
        self.held_by = ()  # who is keeping the machine awake (logged on change)

    # --- input devices: open only while the login screen is on screen
    def scan(self, now):
        self.last_scan = now
        wanted = set(input_devices())
        for fd, path in list(self.fds.items()):
            if path not in wanted:
                self.close(fd)
        have = set(self.fds.values())
        for path in wanted - have:
            # (a test FIFO is opened read-write so it never reports end-of-file)
            flags = os.O_RDWR if INPUT_DIR else os.O_RDONLY
            try:
                fd = os.open(path, flags | os.O_NONBLOCK | os.O_CLOEXEC)
            except OSError:
                continue
            self.fds[fd] = path
            self.watcher.register(fd, select.POLLIN)

    def close(self, fd):
        try:
            self.watcher.unregister(fd)
        except (KeyError, ValueError):
            pass
        try:
            os.close(fd)
        except OSError:
            pass
        self.fds.pop(fd, None)

    def on_input(self, fd, now):
        try:
            data = os.read(fd, EV_RECORD.size * 64)
        except BlockingIOError:
            return
        except OSError:
            self.close(fd)  # unplugged
            return
        for off in range(0, len(data) - EV_RECORD.size + 1, EV_RECORD.size):
            kind = EV_RECORD.unpack_from(data, off)[2]
            if kind not in (EV_SYN, EV_MSC):
                self.activity(now)
                return

    # --- state
    def enter(self, now):
        log("guard: login screen is on screen: idle watch on")
        self.active = True
        self.idle_since = now
        self.next_suspend = 0.0
        self.skew = time.clock_gettime(time.CLOCK_BOOTTIME) - time.monotonic()
        self.scan(now)

    def leave(self):
        log("guard: login screen left: idle watch off")
        self.active = False
        for fd in list(self.fds):
            self.close(fd)
        self.unblank()

    def activity(self, now):
        self.idle_since = now
        self.next_suspend = 0.0
        self.unblank()

    def unblank(self):
        if self.blanked:
            self.blanked = False
            log("guard: screen back on")
            restore_backlights()

    def tick(self, now):
        # CLOCK_BOOTTIME keeps counting while suspended, CLOCK_MONOTONIC does
        # not: a jump between them is a wake-up, which counts as activity (and
        # the screen must not stay dark after one).
        skew = time.clock_gettime(time.CLOCK_BOOTTIME) - time.monotonic()
        woke = skew - self.skew > 2.0
        self.skew = skew
        if woke:
            log("guard: woke from suspend")
            self.activity(now)
            return
        if now - self.last_scan >= INPUT_RESCAN:
            self.scan(now)

        idle_block, sleep_block = blocking_inhibitors()
        held = tuple(sorted(set(idle_block + sleep_block)))
        if held != self.held_by:
            self.held_by = held
            if held:
                log("guard: held awake by: " + ", ".join(held))
            else:
                log("guard: nothing holds the machine awake any more")
        if idle_block:
            # Someone asked for "not idle": the clock does not run.
            self.activity(now)
            return

        idle = now - self.idle_since
        if HUB_BLANK_AFTER > 0 and not self.blanked and idle >= HUB_BLANK_AFTER:
            log(f"guard: login screen idle {int(idle)}s: screen off")
            self.blanked = True
            blank_backlights()
        if HUB_SUSPEND_AFTER > 0 and idle >= HUB_SUSPEND_AFTER and now >= self.next_suspend:
            if sleep_block:
                # logind would refuse: do not try, and do not spin on it either.
                self.next_suspend = now + INHIBIT_RECHECK
                return
            log(f"guard: login screen idle {int(idle)}s: suspending")
            self.next_suspend = time.monotonic() + SUSPEND_RETRY
            try:
                done = subprocess.run(SUSPEND_CMD, capture_output=True, text=True, check=False)
            except OSError as err:
                log(f"guard: cannot suspend: {err}")
                return
            if done.returncode != 0:
                why = (done.stderr or "").strip().splitlines()
                log("guard: suspend refused: " + (why[-1] if why else f"exit {done.returncode}"))
                self.next_suspend = time.monotonic() + SUSPEND_BACKOFF

    def timeout(self, now):
        due = [self.last_scan + INPUT_RESCAN]
        if HUB_BLANK_AFTER > 0 and not self.blanked:
            due.append(self.idle_since + HUB_BLANK_AFTER)
        if HUB_SUSPEND_AFTER > 0:
            due.append(max(self.idle_since + HUB_SUSPEND_AFTER, self.next_suspend))
        if self.held_by:
            # Someone is keeping the machine awake: look again soon, so letting
            # go is noticed promptly (it is just a few small file reads).
            due.append(now + INHIBIT_RECHECK)
        return max(0.05, min(due) - now) * 1000


def main():
    # A guarded VT may be on screen only while a session the hub let in owns
    # it. Two ways that stops being true, and both end at the login screen:
    #   - someone switched in without the hub (Ctrl+Alt+F7, chvt): a live
    #     session there is bounced AT ONCE, nothing of it is shown;
    #   - nothing owns the VT any more: an idle host greeter (boot, or greetd
    #     bringing it back after a logout), or a session that just ended.
    #     Those show nothing, so they get a short grace period: greetd
    #     switches to its VT and then BLOCKS until that VT is on screen
    #     (VT_SETACTIVATE + VT_WAITACTIVE); if the screen were taken away
    #     before that wait begins it would never return and the host could
    #     never hold a session again (the VM test hit exactly this at boot).
    # While a guarded VT is on screen the state is re-checked every second or
    # so (cheap file reads) because a session ending is not a VT switch and
    # gives no other signal.
    watcher = select.poll()
    hub = HubIdle(watcher)
    # A darkened screen left by a previous run (crash, kill) is put back first.
    restore_backlights()

    def finish(*_):
        restore_backlights()
        sys.exit(0)

    signal.signal(signal.SIGTERM, finish)
    signal.signal(signal.SIGINT, finish)
    last = None
    last_live = None
    starting_since = None  # the hub's session is on its way; see below
    arrival_greeters = set()
    idle_since = None
    with open(ACTIVE) as active:
        watcher.register(active, select.POLLPRI | select.POLLERR)
        while True:
            # sysfs only re-arms the notification after a fresh read.
            active.seek(0)
            current = active.read().strip()
            vt = int(current[3:]) if current.startswith("tty") and current[3:].isdigit() else None
            now = time.time()

            if vt != last:
                log(f"guard: screen is now on VT {vt}")
                last = vt
                idle_since = None
                starting_since = None
                if vt in GUARDED:
                    live, arrival_greeters = scan_vt(vt)
                    if consume_token(vt):
                        starting_since = now
                    elif live:
                        bounce(vt, "unauthorised switch into a session")
                        continue

            timeout = None
            if vt in GUARDED:
                if consume_token(vt):  # the hub is about to start a session here
                    starting_since = now
                    _, arrival_greeters = scan_vt(vt)
                live, greeters = scan_vt(vt)
                if live != last_live:
                    last_live = live
                    log(f"guard: VT {vt} {'has a live session' if live else 'has no live session'}")

                # "Starting" lasts until the session shows up, or greetd brings
                # a fresh greeter back (the session already ended), or it is
                # clearly not coming.
                if starting_since is not None and (
                    live
                    or greeters - arrival_greeters
                    or now - starting_since > SESSION_START_WINDOW
                ):
                    starting_since = None

                if live:
                    idle_since = None
                    timeout = RECHECK_LIVE * 1000
                elif starting_since is not None:
                    idle_since = None
                    timeout = 100  # watch closely: it may be gone again within moments
                elif idle_since is None:
                    idle_since = now
                    timeout = IDLE_GRACE * 1000
                elif now - idle_since >= IDLE_GRACE:
                    bounce(vt, "nothing on it")
                    continue
                else:
                    timeout = max(0.05, IDLE_GRACE - (now - idle_since)) * 1000

            # The login screen's own idle handling shares this loop.
            mono = time.monotonic()
            if vt == HUB_VT:
                if not hub.active:
                    hub.enter(mono)
                hub.tick(mono)
                hub_timeout = hub.timeout(mono)
                timeout = hub_timeout if timeout is None else min(timeout, hub_timeout)
            elif hub.active:
                hub.leave()

            for fd, _event in watcher.poll(timeout):
                if fd in hub.fds:
                    hub.on_input(fd, time.monotonic())


if __name__ == "__main__":
    if sys.argv[1:] == ["--restore"]:
        restore_backlights()
    else:
        main()

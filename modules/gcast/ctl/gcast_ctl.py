#!/usr/bin/env python3
"""coel-gcast: cast the screen to Google Cast devices (stdlib only).

coel-gcast scan [seconds]                 list Cast devices on the network
coel-gcast cast <name|address[:port]> [--source portal|test] [engine flags]
                                          start casting (the engine runs as a transient user service)
coel-gcast stop                           stop casting
coel-gcast status                         what the engine is doing
coel-gcast logs                           follow the engine's log

Engine flags are passed through, e.g. --resolution 720p --bitrate 5000 --segment-seconds 2 --no-audio
"""

import asyncio
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE_DIR = os.environ.get("GCAST_ENGINE_DIR", os.path.join(HERE, "..", "engine"))
sys.path.insert(0, ENGINE_DIR)
import discover  # noqa: E402

ENGINE = os.environ.get("GCAST_ENGINE", os.path.join(ENGINE_DIR, "gcast_engine.py"))
SYSTEMD_RUN = os.environ.get("GCAST_SYSTEMD_RUN", "systemd-run")
SYSTEMCTL = os.environ.get("GCAST_SYSTEMCTL", "systemctl")
JOURNALCTL = os.environ.get("GCAST_JOURNALCTL", "journalctl")
UNIT = "gcast-source"
STATUS = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "gcast-source.json")


def status():
    try:
        with open(STATUS) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def stop_engine():
    subprocess.run([SYSTEMCTL, "--user", "stop", UNIT], stderr=subprocess.DEVNULL)
    subprocess.run([SYSTEMCTL, "--user", "reset-failed", UNIT], stderr=subprocess.DEVNULL)


def scan(argv):
    seconds = float(argv[0]) if argv else 4.0
    devices = asyncio.run(discover.browse(seconds))
    if not devices:
        print("no Cast devices found (guest/campus Wi-Fi often isolates clients and blocks mDNS)")
        return 1
    for d in devices:
        print("%-28s %-22s %s:%d" % (d["name"], d["model"], (d["addresses"] or [d["host"]])[0], d["port"]))
    return 0


def resolve(query):
    """Literal address[:port] is used as is; anything else is looked up by name."""
    m = re.fullmatch(r"(\d{1,3}(?:\.\d{1,3}){3})(?::(\d+))?", query)
    if m:
        return {"name": query, "addresses": [m.group(1)], "port": int(m.group(2) or 8009)}
    return discover.find(asyncio.run(discover.browse(4.0)), query)


def cast(argv):
    if not argv:
        sys.exit("usage: coel-gcast cast <name|address[:port]> [--source portal|test] [engine flags]")
    extra = list(argv[1:])
    foreground = "--foreground" in extra
    if foreground:
        extra.remove("--foreground")
    try:
        dev = resolve(argv[0])
    except ValueError as e:
        sys.exit(str(e))
    host = dev["addresses"][0] if dev.get("addresses") else dev["host"]
    if os.environ.get("GCAST_HTTP_PORT") and "--http-port" not in extra:        # services.gcast.httpPort
        extra += ["--http-port", os.environ["GCAST_HTTP_PORT"]]
    cmd = [ENGINE, "--host", host, "--port", str(dev["port"]), "--name", dev["name"]] + extra
    if foreground:                                  # become the engine: signals (Ctrl-C, SIGTERM) reach it directly
        argv = [sys.executable] + cmd if ENGINE.endswith(".py") else cmd
        os.execv(argv[0], argv)
    print("casting to %s (%s:%d)" % (dev["name"], host, dev["port"]))
    stop_engine()
    try:
        os.unlink(STATUS)                       # a previous run's status must not be mistaken for this one's
    except OSError:
        pass
    r = subprocess.run([SYSTEMD_RUN, "--user", "--collect", "--quiet", "--unit", UNIT] + cmd)
    if r.returncode:
        sys.exit("could not start the engine")
    shown = None
    end = time.time() + 240
    while time.time() < end:
        st = status()
        state = st.get("state")
        if state != shown and state:
            shown = state
            note = {"choosing": "pick what to share in the picker that just opened", "preparing": "starting the encoder",
                    "connecting": "connecting to the device", "loading": "starting playback"}.get(state)
            if note:
                print(note)
        if state == "casting":
            print("casting (stop with: coel-gcast stop). Expect a few seconds of delay.")
            return 0
        if state == "error":
            stop_engine()
            sys.exit(st.get("error") or "the engine failed")
        if state == "ended":
            sys.exit("the engine ended: %s" % st.get("reason", ""))
        time.sleep(0.5)
    stop_engine()
    sys.exit("timed out waiting for the device (state: %s)" % shown)


def main(argv):
    cmd = argv[0] if argv else "status"
    if cmd == "scan":
        return scan(argv[1:])
    if cmd == "cast":
        return cast(argv[1:])
    if cmd == "stop":
        stop_engine()
        print("stopped")
    elif cmd == "status":
        st = status()
        print(json.dumps(st, indent=2) if st else "not running")
    elif cmd == "logs":
        subprocess.run([JOURNALCTL, "--user", "-u", UNIT, "-f", "-n", "50"])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]) or 0)

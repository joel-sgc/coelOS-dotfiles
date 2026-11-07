#!/usr/bin/env python3
"""coel-miracast: command-line client for miracast-linkd (stdlib only).

It is just one client of the daemon's two interfaces; anything else (the
Quickshell modal, a keybind script) can use the same ones directly:

  state    /run/miracast/state.json   read it
  control  /run/miracast/linkd.sock   JSON lines, see miracast_linkd.py

  coel-miracast status             one-line summary
  coel-miracast peers [--all]      devices found (sinks only unless --all)
  coel-miracast scan [seconds]     start scanning (default: daemon's default)
  coel-miracast scan-stop          stop scanning
  coel-miracast connect <name|address>
  coel-miracast disconnect
  coel-miracast watch              keep printing the peer list while scanning
  coel-miracast json               raw state.json

  coel-miracast cast <name|address> [--source test|portal]
                                   the whole thing: start the source engine, scan,
                                   connect, wait for the stream to start
  coel-miracast stop               end the cast (drops the link, stops the engine)
  coel-miracast engine             the engine's status
  coel-miracast logs               follow the engine's log
"""

import json
import os
import socket
import subprocess
import sys
import time

STATE = os.environ.get("MIRACAST_STATE", "/run/miracast/state.json")
SOCK = os.environ.get("MIRACAST_SOCKET", "/run/miracast/linkd.sock")
ENGINE = os.environ.get("MIRACAST_ENGINE", "miracast-source")
SYSTEMD_RUN = os.environ.get("MIRACAST_SYSTEMD_RUN", "systemd-run")
SYSTEMCTL = os.environ.get("MIRACAST_SYSTEMCTL", "systemctl")
JOURNALCTL = os.environ.get("MIRACAST_JOURNALCTL", "journalctl")
ENGINE_STATUS = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "miracast-source.json")
ENGINE_UNIT = "miracast-source"


def read_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit("no state file (is miracast-linkd running?  systemctl status miracast-linkd)")


def request(req):
    s = socket.socket(socket.AF_UNIX)
    try:
        s.connect(SOCK)
    except (FileNotFoundError, PermissionError) as e:
        sys.exit("cannot reach %s: %s" % (SOCK, e))
    s.sendall((json.dumps(req) + "\n").encode())
    data = b""
    while not data.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk:
            break
        data += chunk
    s.close()
    return json.loads(data)


def rows(state, show_all):
    peers = [p for p in state["peers"] if show_all or p["is_sink"]]
    if not peers:
        return ["(no devices%s)" % ("" if show_all else "; try 'scan', or --all")]
    out = ["%-24s %-18s %5s  %-14s %s" % ("NAME", "ADDRESS", "RSSI", "ROLE", "AVAILABLE")]
    for p in peers:
        w = p["wfd"]
        out.append("%-24s %-18s %5s  %-14s %s" % (
            (p["name"] or "?")[:24], p["address"], p["rssi"] if p["rssi"] is not None else "",
            w.get("role", "-"), "yes" if w.get("session_available") else "no"))
    return out


def find_peer(state, key):
    key = key.lower()
    exact = [p for p in state["peers"] if p["address"] == key or p["name"].lower() == key]
    if exact:
        return exact[0]
    part = [p for p in state["peers"] if key in p["name"].lower()]
    if len(part) == 1:
        return part[0]
    sys.exit("no unique device matches %r (%d matches)" % (key, len(part)))


def engine_status():
    try:
        with open(ENGINE_STATUS) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def wait_for(what, check, timeout, interval=0.5):
    """Poll check() until it returns a truthy value; exit with a message on timeout."""
    end = time.time() + timeout
    while time.time() < end:
        v = check()
        if v:
            return v
        time.sleep(interval)
    sys.exit("timed out waiting for %s" % what)


def stop_engine():
    subprocess.run([SYSTEMCTL, "--user", "stop", ENGINE_UNIT], stderr=subprocess.DEVNULL)
    subprocess.run([SYSTEMCTL, "--user", "reset-failed", ENGINE_UNIT], stderr=subprocess.DEVNULL)


def cast(argv):
    if not argv:
        sys.exit("usage: coel-miracast cast <name|address> [--source test|portal]")
    key, source = argv[0], "test"
    if "--source" in argv:
        source = argv[argv.index("--source") + 1]

    print("starting the source engine (%s)" % source)
    stop_engine()
    try:                                  # a previous run's status (e.g. its error) must not be mistaken for this one's
        os.unlink(ENGINE_STATUS)
    except OSError:
        pass
    r = subprocess.run([SYSTEMD_RUN, "--user", "--collect", "--quiet", "--unit", ENGINE_UNIT,
                        ENGINE, "--source", source, "--link-state", STATE, "--idle-timeout", "180"])
    if r.returncode:
        sys.exit("could not start the engine")
    if source == "portal":
        print("pick what to share in the picker that just opened")
        wait_for("you to pick what to share (or cancel)",
                 lambda: engine_status().get("state") in ("listening", "error"), 180)
        if engine_status().get("state") == "error":
            e = engine_status().get("error", "")
            stop_engine()
            sys.exit(e or "the engine failed to start")
    wait_for("the engine to listen", lambda: engine_status().get("state") == "listening", 8)

    print("scanning")
    request({"cmd": "scan", "on": True, "seconds": 30})
    peer = wait_for("%r to show up (is it on its Display Mirroring screen?)" % key,
                    lambda: next((p for p in read_state()["peers"]
                                  if key.lower() in (p["address"], p["name"].lower()) or key.lower() in p["name"].lower()), None), 30)
    print("found %s (%s), connecting" % (peer["name"], peer["address"]))
    reply = request({"cmd": "connect", "address": peer["address"]})
    if not reply.get("ok"):
        stop_engine()
        sys.exit("connect failed: %s" % reply.get("error"))

    seen = {"attempt": 1}

    def link_done():
        link = read_state()["link"]
        if link.get("attempt", 1) != seen["attempt"]:
            seen["attempt"] = link["attempt"]
            print("attempt %d (the last one failed: %s)" % (link["attempt"], link.get("last_failure", "?")))
        return link if link["state"] in ("ready", "error") else None
    link = wait_for("the link", link_done, 150)
    if link["state"] == "error":
        stop_engine()
        sys.exit("link failed: %s" % link.get("reason"))
    print("linked: we are %s, TV is %s" % (link["local_ip"], link["remote_ip"]))

    def streaming():
        e = engine_status()
        return e if e.get("state") in ("streaming", "error", "ended") else None
    e = wait_for("the TV to start the stream", streaming, 60)
    if e["state"] == "streaming":
        m = e.get("mode", {})
        print("streaming %sx%s@%s (stop with: coel-miracast stop)" % (m.get("width"), m.get("height"), m.get("fps")))
    else:
        print("the engine stopped: %s %s" % (e.get("state"), e.get("error") or e.get("reason") or ""))
        print("see: coel-miracast logs")
        sys.exit(1)


def main(argv):
    cmd = argv[0] if argv else "status"
    if cmd == "status":
        s = read_state()
        link = s["link"]["state"]
        print("wpa: %s  iface: %s  scanning: %s  link: %s  devices: %d"
              % (s["wpa"], s["interface"], s["scanning"], link, len(s["peers"])))
        if s["error"]:
            print("error:", s["error"])
        e = engine_status()
        if e:
            print("engine: %s%s" % (e.get("state"), "  (%s)" % e["error"] if e.get("error") else ""))
    elif cmd == "peers":
        print("\n".join(rows(read_state(), "--all" in argv)))
    elif cmd == "scan":
        req = {"cmd": "scan", "on": True}
        if len(argv) > 1:
            req["seconds"] = int(argv[1])
        print(request(req))
    elif cmd == "scan-stop":
        print(request({"cmd": "scan", "on": False}))
    elif cmd == "connect":
        if len(argv) < 2:
            sys.exit("usage: coel-miracast connect <name|address>")
        peer = find_peer(read_state(), argv[1])
        print("connecting to %s (%s)" % (peer["name"], peer["address"]))
        print(request({"cmd": "connect", "address": peer["address"]}))
    elif cmd == "disconnect":
        print(request({"cmd": "disconnect"}))
    elif cmd == "cast":
        cast(argv[1:])
    elif cmd == "stop":
        print(request({"cmd": "disconnect"}))
        stop_engine()
    elif cmd == "engine":
        print(json.dumps(engine_status(), indent=2))
    elif cmd == "logs":
        subprocess.run([JOURNALCTL, "--user", "-u", ENGINE_UNIT, "-f", "-n", "50"])
    elif cmd == "json":
        print(json.dumps(read_state(), indent=2))
    elif cmd == "watch":
        request({"cmd": "scan", "on": True})
        try:
            while True:
                s = read_state()
                print("\033[2J\033[H" + "\n".join(rows(s, False)))
                time.sleep(1)
        except KeyboardInterrupt:
            pass
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])

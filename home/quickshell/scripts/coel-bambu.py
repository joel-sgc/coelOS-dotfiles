#!/usr/bin/env python3
"""Bambu Lab P1S status for the Quickshell island (../island/sources/PrinterSource.qml).

Run by Quickshell as a child process. Stdlib only, so it runs straight from the
repo and hot-reloads with the shell. Talks to the printer over its LAN MQTT
(TLS :8883, user "bblp", password = access code; commands need LAN-only +
Developer Mode) and grabs camera frames from the P1-series JPEG stream (TLS :6000).

Out (stdout, one JSON object per line):
  {"type":"config","ok":false,"error":...}   no credentials (run coel-bambu-setup)
  {"type":"reach","ok":bool,"last_seen":ms}  printer reachable or not (it is only
                                             reachable over Tailscale, so "not" is routine)
  {"type":"state", ...normalized fields...}  see normalize()
  {"type":"snapshot","path":...,"at":ms}
  {"type":"ack","cmd":...,"ok":bool,"error":...}
In (stdin, one JSON object per line):
  {"cmd":"pause"|"resume"|"stop"|"refresh"|"snapshot"}

Polling: with nothing printing it connects every IDLE_POLL seconds, asks for a
full report, and disconnects. Once a print is active it stays connected (the
printer pushes deltas) until the print ends. Unreachable: an active print retries
with backoff (RETRY_ACTIVE), an idle printer just waits for the next idle poll.
"""

import json
import os
import select
import socket
import ssl
import struct
import subprocess
import sys
import time

IDLE_POLL = 300           # s between idle check-ins
PUSHALL_EVERY = 300       # s between full-state requests while connected (P1s dislike more)
SNAPSHOT_EVERY = 60       # s between camera frames while printing
KEEPALIVE = 20            # s between MQTT pings while connected
DEAD_AFTER = 45           # s with no traffic at all (a dropped Tailscale route goes silent, no FIN)
RETRY_ACTIVE = [20, 40, 90, 180, 300]
CONNECT_TIMEOUT = 6
CANCELLED = 0x0300400C    # print_error after a user cancel: not a failure
ACTIVE = {"RUNNING", "PREPARE", "SLICING", "PAUSE"}
SPEEDS = {1: "silent", 2: "standard", 3: "sport", 4: "ludicrous"}

SNAP_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "coel-bambu")


def now_ms():
    return int(time.time() * 1000)


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def log(*a):
    print("coel-bambu:", *a, file=sys.stderr, flush=True)


def load_creds():
    """{"host","serial","access_code","name"} from the keyring via coel-bambu-setup."""
    try:
        out = subprocess.run(["coel-bambu-setup", "get"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "coel-bambu-setup not available: %s" % e
    if out.returncode != 0 or not out.stdout.strip():
        return None, "no printer configured (run coel-bambu-setup)"
    try:
        c = json.loads(out.stdout)
        for k in ("host", "serial", "access_code"):
            if not c.get(k):
                return None, "keyring entry is missing %s" % k
        return c, None
    except ValueError:
        return None, "keyring entry is not JSON"


def tls_connect(host, port):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # the printer's certificate is self-signed
    raw = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
    try:
        return ctx.wrap_socket(raw, server_hostname=host)
    except Exception:
        raw.close()
        raise


# ---------------------------------------------------------------- minimal MQTT 3.1.1 (QoS 0)

def _str(s):
    b = s.encode()
    return struct.pack("!H", len(b)) + b


def _packet(header, body):
    n, out = len(body), bytearray([header])
    while True:
        byte, n = n % 128, n // 128
        out.append(byte | (0x80 if n else 0))
        if not n:
            break
    return bytes(out) + body


class Mqtt:
    def __init__(self, host, user, password, serial):
        self.serial = serial
        self.sock = tls_connect(host, 8883)
        self.buf = b""
        self.last_rx = time.monotonic()
        self.last_tx = time.monotonic()
        cid = "coel-island-%d" % os.getpid()
        body = _str("MQTT") + bytes([4, 0xC2]) + struct.pack("!H", 60) + _str(cid) + _str(user) + _str(password)
        self._send(_packet(0x10, body))
        ptype, payload = self._read_packet(blocking=True)
        if ptype != 2 or len(payload) < 2 or payload[1] != 0:
            raise ConnectionError("MQTT connect refused (rc=%s): wrong access code?" % (payload[1] if len(payload) > 1 else "?"))
        self._send(_packet(0x82, struct.pack("!H", 1) + _str("device/%s/report" % serial) + b"\x00"))

    def fileno(self):
        return self.sock.fileno()

    def _send(self, data):
        self.sock.sendall(data)
        self.last_tx = time.monotonic()

    def publish(self, obj):
        self._send(_packet(0x30, _str("device/%s/request" % self.serial) + json.dumps(obj).encode()))

    def ping(self):
        self._send(b"\xc0\x00")

    def close(self):
        try:
            self._send(b"\xe0\x00")
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass

    def _fill(self, blocking):
        self.sock.settimeout(CONNECT_TIMEOUT if blocking else 0.0)
        try:
            chunk = self.sock.recv(65536)
        except (ssl.SSLWantReadError, BlockingIOError):
            return False
        if not chunk:
            raise ConnectionError("printer closed the connection")
        self.buf += chunk
        self.last_rx = time.monotonic()
        return True

    def _parse(self):
        """One complete packet from the buffer, or None."""
        if len(self.buf) < 2:
            return None
        mult, n, i = 1, 0, 1
        while True:
            if i >= len(self.buf):
                return None
            b = self.buf[i]
            n += (b & 0x7F) * mult
            mult *= 128
            i += 1
            if not b & 0x80:
                break
            if i > 4:
                raise ConnectionError("bad MQTT length")
        if len(self.buf) < i + n:
            return None
        header, body = self.buf[0], self.buf[i:i + n]
        self.buf = self.buf[i + n:]
        return header >> 4, (header & 0x0F, body) if header >> 4 == 3 else body

    def _read_packet(self, blocking):
        while True:
            p = self._parse()
            if p is not None:
                return p
            if not self._fill(blocking) and not blocking:
                return None, None

    def messages(self):
        """Every JSON report that is fully buffered or readable right now."""
        out = []
        while self._fill(False):  # drain: TLS may hold decoded bytes select() can't see
            pass
        while True:
            p = self._parse()
            if p is None:
                return out
            ptype, data = p
            if ptype == 3:
                flags, body = data
                tlen = struct.unpack("!H", body[:2])[0]
                off = 2 + tlen + (2 if flags & 0x06 else 0)
                try:
                    out.append(json.loads(body[off:]))
                except ValueError:
                    pass


# ---------------------------------------------------------------- camera (P1/A1 JPEG stream)

def grab_frame(host, code):
    s = tls_connect(host, 6000)
    try:
        s.settimeout(8)
        s.sendall(struct.pack("<IIII", 0x40, 0x3000, 0, 0) + b"bblp".ljust(32, b"\0") + code.encode().ljust(32, b"\0"))

        def read(n):
            b = b""
            while len(b) < n:
                c = s.recv(n - len(b))
                if not c:
                    raise ConnectionError("camera stream closed")
                b += c
            return b

        size = struct.unpack("<I", read(16)[:4])[0]
        if not 0 < size < 8 * 1024 * 1024:
            raise ValueError("bad frame size %d" % size)
        img = read(size)
        if img[:2] != b"\xff\xd8" or img[-2:] != b"\xff\xd9":
            raise ValueError("not a JPEG frame")
        return img
    finally:
        s.close()


# ---------------------------------------------------------------- printer state

def _i(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return 0


def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def normalize(p, name):
    g = p.get("gcode_state", "IDLE")
    err = _i(p.get("print_error"))
    if g in ("RUNNING", "PREPARE", "SLICING"):
        status = "printing"
    elif g == "PAUSE":
        status = "paused"
    elif g == "FINISH":
        status = "finished"
    elif g == "FAILED":
        status = "idle" if err == CANCELLED else "failed"
    else:
        status = "idle"
    fault = (status == "paused" and err not in (0, CANCELLED)) or status == "failed"
    try:
        fan = round(_i(p.get("cooling_fan_speed")) / 15 * 100)
    except ValueError:
        fan = 0
    code = "%08X" % err
    return {
        "type": "state",
        "name": name,
        "status": status,
        "gcode_state": g,
        "fault": fault,
        "error_code": (code[:4] + "_" + code[4:]) if err else "",
        "file": p.get("subtask_name") or p.get("gcode_file") or "",
        "pct": _i(p.get("mc_percent")),
        "layer": _i(p.get("layer_num")),
        "total_layers": _i(p.get("total_layer_num")),
        "remaining_min": _i(p.get("mc_remaining_time")),
        "nozzle": _f(p.get("nozzle_temper")),
        "nozzle_target": _f(p.get("nozzle_target_temper")),
        "bed": _f(p.get("bed_temper")),
        "bed_target": _f(p.get("bed_target_temper")),
        "speed": SPEEDS.get(_i(p.get("spd_lvl")) or 2, "standard"),
        "fan": fan,
        "start_time": _i(p.get("gcode_start_time")),
        "seen": now_ms(),
    }


class Daemon:
    def __init__(self, creds):
        self.c = creds
        self.name = creds.get("name") or "Bambu P1S"
        self.mqtt = None
        self.raw = {}            # merged "print" object (P1s send deltas)
        self.last_state = None
        self.reachable = None
        self.last_seen = 0
        self.next_poll = 0       # monotonic time of the next idle check-in / retry
        self.retry_i = 0
        self.last_pushall = 0
        self.last_snapshot = 0
        self.last_ping = 0
        self.stdin_buf = b""

    @property
    def active(self):
        return self.raw.get("gcode_state") in ACTIVE

    def set_reach(self, ok):
        if ok:
            self.last_seen = now_ms()
            self.retry_i = 0
        if ok != self.reachable:
            self.reachable = ok
            emit({"type": "reach", "ok": ok, "last_seen": self.last_seen})

    def connect(self):
        try:
            self.mqtt = Mqtt(self.c["host"], "bblp", self.c["access_code"], self.c["serial"])
        except (OSError, ConnectionError, ssl.SSLError) as e:
            log("connect failed:", e)
            self.mqtt = None
            self.set_reach(False)
            return False
        self.set_reach(True)
        self.pushall()
        return True

    def drop(self, why):
        log("disconnected:", why)
        if self.mqtt:
            self.mqtt.close()
        self.mqtt = None

    def pushall(self):
        self.mqtt.publish({"pushing": {"sequence_id": "0", "command": "pushall", "version": 1, "push_target": 1}})
        self.last_pushall = time.monotonic()

    def ingest(self, msgs):
        changed = False
        for m in msgs:
            p = m.get("print")
            if isinstance(p, dict):
                self.raw.update(p)
                changed = True
        if not changed:
            return False
        self.set_reach(True)
        st = normalize(self.raw, self.name)
        prev = self.last_state
        key = {k: v for k, v in st.items() if k != "seen"}
        if prev is None or key != {k: v for k, v in prev.items() if k != "seen"}:
            emit(st)
        # A frame at the moments worth seeing: the print ends, fails, or pauses itself.
        if prev and prev["status"] != st["status"] and st["status"] in ("finished", "failed", "paused"):
            self.snapshot()
        self.last_state = st
        return True

    def snapshot(self):
        self.last_snapshot = time.monotonic()
        try:
            img = grab_frame(self.c["host"], self.c["access_code"])
        except Exception as e:
            log("snapshot failed:", e)
            return False
        os.makedirs(SNAP_DIR, mode=0o700, exist_ok=True)
        at = now_ms()
        path = os.path.join(SNAP_DIR, "snap-%d.jpg" % at)
        with open(path + ".tmp", "wb") as f:
            f.write(img)
        os.rename(path + ".tmp", path)
        for old in os.listdir(SNAP_DIR):
            if old.startswith("snap-") and old != os.path.basename(path):
                try:
                    os.remove(os.path.join(SNAP_DIR, old))
                except OSError:
                    pass
        emit({"type": "snapshot", "path": path, "at": at})
        return True

    def command(self, cmd):
        if cmd == "refresh":
            self.next_poll = 0
            if self.mqtt:
                self.pushall()
            return emit({"type": "ack", "cmd": cmd, "ok": True})
        if cmd == "snapshot":
            ok = self.snapshot()
            return emit({"type": "ack", "cmd": cmd, "ok": ok, "error": "" if ok else "camera unreachable"})
        if cmd not in ("pause", "resume", "stop"):
            return emit({"type": "ack", "cmd": cmd, "ok": False, "error": "unknown command"})
        if not self.mqtt and not self.connect():
            return emit({"type": "ack", "cmd": cmd, "ok": False, "error": "printer unreachable"})
        try:
            self.mqtt.publish({"print": {"sequence_id": "0", "command": cmd, "param": ""}})
            emit({"type": "ack", "cmd": cmd, "ok": True})
        except OSError as e:
            self.drop(e)
            self.set_reach(False)
            emit({"type": "ack", "cmd": cmd, "ok": False, "error": "printer unreachable"})

    def read_stdin(self):
        chunk = os.read(sys.stdin.fileno(), 4096)
        if not chunk:
            log("stdin closed, exiting")
            sys.exit(0)
        self.stdin_buf += chunk
        while b"\n" in self.stdin_buf:
            line, self.stdin_buf = self.stdin_buf.split(b"\n", 1)
            try:
                self.command(json.loads(line).get("cmd", ""))
            except ValueError:
                pass

    def schedule_after_loss(self):
        if self.active:  # a print was running: come back soon
            self.next_poll = time.monotonic() + RETRY_ACTIVE[min(self.retry_i, len(RETRY_ACTIVE) - 1)]
            self.retry_i += 1
        else:
            self.next_poll = time.monotonic() + IDLE_POLL

    def run(self):
        while True:
            t = time.monotonic()
            if not self.mqtt and t >= self.next_poll:
                if self.connect():
                    # Idle check-in: collect the full report, then hang up unless printing.
                    deadline, got = time.monotonic() + 4, False
                    while time.monotonic() < deadline and self.mqtt:
                        r, _, _ = select.select([self.mqtt, sys.stdin], [], [], 0.5)
                        if sys.stdin in r:
                            self.read_stdin()
                        if self.mqtt and self.mqtt in r:
                            try:
                                got = self.ingest(self.mqtt.messages()) or got
                            except (OSError, ConnectionError, ssl.SSLError) as e:
                                self.drop(e)
                                self.set_reach(False)
                        if got and self.raw.get("gcode_state"):
                            break
                    if self.mqtt and not self.active:
                        self.drop("idle check-in done")
                        self.next_poll = time.monotonic() + IDLE_POLL
                    elif not self.mqtt:
                        self.schedule_after_loss()
                    if self.mqtt and self.active and time.monotonic() - self.last_snapshot > SNAPSHOT_EVERY:
                        self.snapshot()
                else:
                    self.schedule_after_loss()

            fds = [sys.stdin] + ([self.mqtt] if self.mqtt else [])
            wait = 1.0 if self.mqtt else max(0.2, min(5.0, self.next_poll - time.monotonic()))
            r, _, _ = select.select(fds, [], [], wait)
            if sys.stdin in r:
                self.read_stdin()
            if not self.mqtt:
                continue
            t = time.monotonic()
            try:
                if self.mqtt in r:
                    self.ingest(self.mqtt.messages())
                if t - self.mqtt.last_rx > DEAD_AFTER:
                    raise ConnectionError("no traffic for %ds" % DEAD_AFTER)
                if t - self.mqtt.last_tx > KEEPALIVE:
                    self.mqtt.ping()
                if t - self.last_pushall > PUSHALL_EVERY:
                    self.pushall()
            except (OSError, ConnectionError, ssl.SSLError) as e:
                self.drop(e)
                self.set_reach(False)
                self.schedule_after_loss()
                continue
            if not self.active:
                self.drop("print no longer active")
                self.next_poll = t + IDLE_POLL
            elif t - self.last_snapshot > SNAPSHOT_EVERY:
                self.snapshot()


def main():
    while True:
        creds, err = load_creds()
        if creds:
            break
        emit({"type": "config", "ok": False, "error": err})
        # Wait for setup (or a command) without spinning.
        r, _, _ = select.select([sys.stdin], [], [], 60)
        if r and not os.read(sys.stdin.fileno(), 4096):
            return
    emit({"type": "config", "ok": True, "name": creds.get("name") or "Bambu P1S"})
    Daemon(creds).run()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass

#!/usr/bin/env python3
"""Read Fn / Fn-lock state from a patched Framework 13 AMD EC.

Requires the EC patch that adds host command 0x3EF0 (EC_CMD_GET_FN_STATE)
and the kernel's cros_ec driver exposing /dev/cros_ec. Needs root.

  fnlock-state.py                  print "locked" or "unlocked" once
  fnlock-state.py --json           one waybar-style JSON line
  fnlock-state.py --watch          print a line every time the state changes
  fnlock-state.py --watch --state-file /run/fnlock/state
                                   also keep that file updated (for a service)
  fnlock-state.py --watch --on-change 'cmd'
                                   run cmd on every change; FNLOCK=locked|unlocked
"""
import argparse
import fcntl
import json
import os
import struct
import subprocess
import sys
import tempfile
import time

EC_CMD_GET_FN_STATE = 0x3EF0
DEV = "/dev/cros_ec"

# struct cros_ec_command { u32 version, command, outsize, insize, result; u8 data[]; }
HDR = struct.Struct("<5I")
# _IOWR(0xEC, 0, struct cros_ec_command) with a 20-byte header
CROS_EC_DEV_IOCXCMD = (3 << 30) | (HDR.size << 16) | (0xEC << 8) | 0

FN_PRESSED = 1 << 0
FN_LOCKED = 1 << 1


def read_state(f) -> int:
    insize = 1
    buf = bytearray(HDR.pack(0, EC_CMD_GET_FN_STATE, 0, insize, 0) + b"\0" * insize)
    fcntl.ioctl(f, CROS_EC_DEV_IOCXCMD, buf, True)
    _, _, _, _, result = HDR.unpack_from(buf)
    if result != 0:
        raise RuntimeError(f"EC returned error {result} (unpatched EC?)")
    return buf[HDR.size]


def label(locked: bool) -> str:
    return "locked" if locked else "unlocked"


def as_json(locked: bool) -> str:
    return json.dumps({
        "text": "FnLock" if locked else "",
        "class": label(locked),
        "alt": label(locked),
        "tooltip": f"Fn lock {'on' if locked else 'off'}",
    })


def write_state_file(path: str, locked: bool) -> None:
    """Atomically replace the file so readers never see a partial write."""
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d)
    with os.fdopen(fd, "w") as t:
        t.write(label(locked) + "\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def watch(args) -> int:
    last = None
    f = None
    while True:
        try:
            if f is None:
                f = open(DEV, "rb", buffering=0)
            locked = bool(read_state(f) & FN_LOCKED)
        except RuntimeError as e:  # EC answered but doesn't know the command
            print(f"error: {e}", file=sys.stderr)
            return 1
        except OSError:
            # Transient (e.g. during suspend/resume): reopen and retry.
            if f is not None:
                f.close()
                f = None
            time.sleep(1)
            continue

        if locked != last:
            last = locked
            print(as_json(locked) if args.json else label(locked), flush=True)
            if args.state_file:
                write_state_file(args.state_file, locked)
            if args.on_change:
                subprocess.Popen(args.on_change, shell=True,
                                 env={**os.environ, "FNLOCK": label(locked)})
        time.sleep(args.interval)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--json", action="store_true")
    p.add_argument("--watch", action="store_true")
    p.add_argument("--interval", type=float, default=0.2,
                   help="seconds between checks in --watch mode (default 0.2)")
    p.add_argument("--state-file")
    p.add_argument("--on-change")
    args = p.parse_args()

    if args.watch:
        try:
            return watch(args)
        except KeyboardInterrupt:
            return 0

    try:
        with open(DEV, "rb", buffering=0) as f:
            locked = bool(read_state(f) & FN_LOCKED)
    except Exception as e:  # noqa: BLE001
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(as_json(locked) if args.json else label(locked))
    return 0


if __name__ == "__main__":
    sys.exit(main())

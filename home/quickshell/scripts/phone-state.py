#!/usr/bin/env python3
"""One-shot KDE Connect snapshot for the desktop's phone card (services/Phone.qml).

Prints one JSON object:
  {"ok": true, "id", "name", "reachable", "battery" (-1 unknown), "charging",
   "notification": {"id", "app", "title", "text"} | null}
or {"ok": false, "error"} when there's no daemon or no paired device.

Uses busctl (systemd) so it needs no Python D-Bus module. The plugin objects
(battery, notifications) only exist while the phone is reachable.
"""
import json
import subprocess
import sys

BUS = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"


def busctl(*args):
    out = subprocess.run(["busctl", "--user", "--json=short", *args],
                         capture_output=True, text=True, timeout=5)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "busctl failed")
    return json.loads(out.stdout)["data"] if out.stdout.strip() else None


def prop(path, iface, name, default=None):
    try:
        return busctl("get-property", BUS, path, iface, name)
    except (RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired):
        return default


def main():
    try:
        devices = busctl("call", BUS, ROOT, "org.kde.kdeconnect.daemon", "devices", "bb", "false", "true")[0]
    except Exception as e:  # no daemon, no bus, ...
        return {"ok": False, "error": str(e)}
    if not devices:
        return {"ok": False, "error": "no paired phone"}
    # Prefer one that's reachable right now.
    dev = None
    for d in devices:
        if prop(f"{ROOT}/devices/{d}", "org.kde.kdeconnect.device", "isReachable", False):
            dev = d
            break
    dev = dev or devices[0]
    base = f"{ROOT}/devices/{dev}"
    res = {
        "ok": True, "id": dev,
        "name": prop(base, "org.kde.kdeconnect.device", "name", "phone"),
        "reachable": bool(prop(base, "org.kde.kdeconnect.device", "isReachable", False)),
        "battery": -1, "charging": False, "notification": None,
    }
    if not res["reachable"]:
        return res
    res["battery"] = prop(f"{base}/battery", "org.kde.kdeconnect.device.battery", "charge", -1)
    res["charging"] = bool(prop(f"{base}/battery", "org.kde.kdeconnect.device.battery", "isCharging", False))
    try:
        ids = busctl("call", BUS, f"{base}/notifications", "org.kde.kdeconnect.device.notifications", "activeNotifications")[0]
    except Exception:
        ids = []
    if ids:
        nid = ids[-1]
        npath = f"{base}/notifications/{nid}"
        iface = "org.kde.kdeconnect.device.notifications.notification"
        res["notification"] = {
            "id": nid,
            "app": prop(npath, iface, "appName", ""),
            "title": prop(npath, iface, "title", ""),
            "text": prop(npath, iface, "text", ""),
        }
    return res


if __name__ == "__main__":
    print(json.dumps(main()))
    sys.stdout.flush()

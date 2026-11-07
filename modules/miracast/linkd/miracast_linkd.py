#!/usr/bin/env python3
"""miracast-linkd: privileged Wi-Fi Direct (P2P) link daemon for Miracast.

Runs as root because wpa_supplicant's D-Bus API is root-only. Everything an
unprivileged client (CLI, Quickshell, a keybind) needs is exposed through two
plain interfaces so no client is tied to D-Bus or to wpa_supplicant:

  state file     /run/miracast/state.json   (world-readable, replaced atomically)
  control socket /run/miracast/linkd.sock   (JSON lines; group-writable)

It deliberately does NOT go through NetworkManager's Wi-Fi P2P support: on
NetworkManager 1.56 the peers wpa_supplicant announces never reach NM's peer
list (see ../README.md). Talking to wpa_supplicant directly avoids that.

Control protocol: one JSON object per line in, one JSON object per line out.

  {"cmd": "status"}
  {"cmd": "scan", "on": true, "seconds": 60}
  {"cmd": "connect", "address": "6a:9a:87:3c:4e:b4", "go_intent": 0}
  {"cmd": "disconnect"}
  {"cmd": "flush"}

Replies are {"ok": true, ...} or {"ok": false, "error": "..."}.
"""

import argparse
import asyncio
import grp
import json
import os
import signal
import sys
import tempfile
import time

WPA_NAME = "fi.w1.wpa_supplicant1"
WPA_ROOT = "/fi/w1/wpa_supplicant1"
IF_ROOT = "fi.w1.wpa_supplicant1"
IF_IFACE = "fi.w1.wpa_supplicant1.Interface"
IF_P2P = "fi.w1.wpa_supplicant1.Interface.P2PDevice"
IF_PEER = "fi.w1.wpa_supplicant1.Peer"
IF_PROPS = "org.freedesktop.DBus.Properties"

# WFD subelement 0 (device information), as sent in the P2P IEs:
#   id(1) len(2) | dev_info(2) port(2) max_throughput(2)
# dev_info 0x0010: primary role "source", session available.
WFD_SOURCE_DEVINFO = 0x0010

ROLE_NAMES = {0: "source", 1: "sink", 2: "secondary-sink", 3: "dual"}

SYSTEMD = "org.freedesktop.systemd1"
SYSTEMD_PATH = "/org/freedesktop/systemd1"
SYSTEMD_MANAGER = "org.freedesktop.systemd1.Manager"


# ----------------------------------------------------------------------------
# Pure helpers (no D-Bus): unit-tested in test_miracast_linkd.py
# ----------------------------------------------------------------------------

def mac_str(raw):
    """bytes/list of 6 ints -> 'aa:bb:cc:dd:ee:ff'."""
    return ":".join("%02x" % b for b in bytes(raw))


def mac_from_peer_path(path):
    """'.../Peers/6a9a873c4eb4' -> '6a:9a:87:3c:4e:b4'."""
    tail = path.rsplit("/", 1)[-1]
    if len(tail) != 12:
        return None
    return ":".join(tail[i:i + 2] for i in range(0, 12, 2)).lower()


def primary_device_type(raw):
    """WSC primary device type bytes -> 'category-OUI-subcategory'."""
    b = bytes(raw)
    if len(b) != 8:
        return ""
    return "%d-%s-%d" % (int.from_bytes(b[0:2], "big"), b[2:6].hex().upper(),
                         int.from_bytes(b[6:8], "big"))


def parse_wfd_ies(raw):
    """Parse the WFD subelements of a peer's IEs. Returns a dict (maybe empty)."""
    b = bytes(raw)
    out = {}
    i = 0
    while i + 3 <= len(b):
        sub_id = b[i]
        ln = (b[i + 1] << 8) | b[i + 2]
        payload = b[i + 3:i + 3 + ln]
        i += 3 + ln
        if sub_id == 0 and len(payload) >= 6:
            dev_info = (payload[0] << 8) | payload[1]
            role = dev_info & 0x3
            out = {
                "present": True,
                "role": ROLE_NAMES.get(role, "unknown"),
                "is_sink": role in (1, 2, 3),
                "session_available": ((dev_info >> 4) & 0x3) == 1,
                "content_protection": bool(dev_info & 0x100),
                "port": (payload[2] << 8) | payload[3],
                "max_throughput": (payload[4] << 8) | payload[5],
            }
    return out


def parse_lease(text):
    """Parse the JSON lease the DHCP helper writes. Returns None if unusable."""
    try:
        d = json.loads(text)
    except ValueError:
        return None
    if not isinstance(d, dict) or not d.get("ip"):
        return None
    router = (d.get("router") or d.get("serverid") or "").split()
    return {"ip": d["ip"], "mask": d.get("mask"), "router": router[0] if router else None}


def build_wfd_ies(port, throughput):
    """The WFD IE bytes we advertise: a source, session available."""
    return bytes([0x00, 0x00, 0x06,
                  (WFD_SOURCE_DEVINFO >> 8) & 0xFF, WFD_SOURCE_DEVINFO & 0xFF,
                  (port >> 8) & 0xFF, port & 0xFF,
                  (throughput >> 8) & 0xFF, throughput & 0xFF])


def peer_record(props, now=None):
    """Build the published record for a peer from wpa_supplicant's properties
    (plain Python values, variants already unwrapped)."""
    now = time.time() if now is None else now
    wfd = parse_wfd_ies(props.get("IEs", b""))
    return {
        "address": mac_str(props["DeviceAddress"]) if props.get("DeviceAddress") else "",
        "name": (props.get("DeviceName") or "").strip(),
        "manufacturer": (props.get("Manufacturer") or "").strip(),
        "model": (props.get("ModelName") or props.get("Model") or "").strip(),
        "device_type": primary_device_type(props.get("PrimaryDeviceType", b"")),
        "rssi": props.get("level"),
        "group_capability": props.get("groupcapability"),
        "wfd": wfd,
        "is_sink": bool(wfd.get("is_sink")),
        "last_seen": now,
    }


class State:
    """What the daemon knows; serialised to state.json."""

    def __init__(self, peer_ttl):
        self.peer_ttl = peer_ttl
        self.peers = {}          # address -> record
        self.scanning = False
        self.scan_until = 0.0
        self.link = {"state": "idle"}   # idle | connecting | connected | error
        self.wpa = "down"        # down | up
        self.interface = None
        self.error = ""

    def expire(self, now=None):
        now = time.time() if now is None else now
        dead = [a for a, p in self.peers.items() if now - p["last_seen"] > self.peer_ttl]
        for a in dead:
            del self.peers[a]
        return bool(dead)

    def to_json(self, now=None):
        now = time.time() if now is None else now
        peers = sorted(self.peers.values(), key=lambda p: (not p["is_sink"], p["name"].lower()))
        return {
            "version": 1,
            "updated": now,
            "wpa": self.wpa,
            "interface": self.interface,
            "scanning": self.scanning,
            "scan_remaining": max(0, int(self.scan_until - now)) if self.scanning else 0,
            "link": self.link,
            "error": self.error,
            "peers": [dict(p, age=round(now - p["last_seen"], 1)) for p in peers],
        }


def write_atomic(path, data):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".state-")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


# ----------------------------------------------------------------------------
# wpa_supplicant over D-Bus
# ----------------------------------------------------------------------------

def unwrap(v):
    """dbus_fast Variants -> plain Python."""
    from dbus_fast import Variant
    if isinstance(v, Variant):
        return unwrap(v.value)
    if isinstance(v, dict):
        return {k: unwrap(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [unwrap(x) for x in v]
    return v


class Daemon:
    def __init__(self, args):
        self.args = args
        self.state = State(args.peer_ttl)
        self.bus = None
        self.path = None                 # wpa Interface object path (has the P2PDevice iface)
        self.want_scan = False
        self.dirty = asyncio.Event()
        self.group_iface_path = None
        self.connect_deadline = 0.0
        self.connect_addr = None
        self.connect_args = None
        self.connect_attempt = 0

    # --- D-Bus plumbing ---------------------------------------------------
    async def call(self, path, iface, member, sig="", body=None, dest=WPA_NAME):
        from dbus_fast import Message, MessageType
        reply = await self.bus.call(Message(destination=dest, path=path, interface=iface,
                                            member=member, signature=sig, body=body or []))
        if reply.message_type == MessageType.ERROR:
            raise RuntimeError("%s.%s: %s" % (iface, member, reply.body[0] if reply.body else reply.error_name))
        return reply

    async def get_prop(self, path, iface, name):
        r = await self.call(path, IF_PROPS, "Get", "ss", [iface, name])
        return unwrap(r.body[0])

    async def set_prop(self, path, iface, name, variant):
        await self.call(path, IF_PROPS, "Set", "ssv", [iface, name, variant])

    async def add_match(self, rule):
        await self.call("/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch", "s", [rule],
                        dest="org.freedesktop.DBus")

    # --- interface discovery ---------------------------------------------
    async def resolve_interface(self):
        """Find the wpa Interface that carries the P2PDevice API."""
        paths = await self.get_prop(WPA_ROOT, IF_ROOT, "Interfaces")
        for p in paths:
            try:
                name = await self.get_prop(p, IF_IFACE, "Ifname")
            except Exception:
                continue
            if self.args.interface and name != self.args.interface:
                continue
            if not self.args.interface and name.startswith("p2p-"):
                continue
            try:
                await self.get_prop(p, IF_P2P, "Peers")
            except Exception:
                continue
            return p, name
        return None, None

    async def attach(self):
        path, name = await self.resolve_interface()
        if not path:
            return False
        self.path = path
        self.state.interface = name
        self.state.wpa = "up"
        self.state.error = ""
        self.state.peers.clear()
        self.state.link = {"state": "idle"}      # any old link died with the old interface
        await self.advertise_wfd()
        # peers already known to wpa_supplicant are only announced again once
        # re-found, so seed from the object tree
        try:
            for peer_path in await self.get_prop(path, IF_P2P, "Peers"):
                await self.load_peer(peer_path)
        except Exception as e:
            print("seeding peers failed: %s" % e, file=sys.stderr)
        self.touch()
        print("attached to %s (%s)" % (name, path), flush=True)
        if self.want_scan:
            await self.start_find()
        return True

    async def advertise_wfd(self):
        from dbus_fast import Variant
        ies = build_wfd_ies(self.args.rtsp_port, self.args.throughput)
        try:
            await self.set_prop(WPA_ROOT, IF_ROOT, "WFDIEs", Variant("ay", ies))
        except Exception as e:
            print("could not set WFDIEs: %s" % e, file=sys.stderr)
        if self.args.device_name:
            try:
                cfg = await self.get_prop(self.path, IF_P2P, "P2PDeviceConfig")
                cfg["DeviceName"] = self.args.device_name
                await self.set_prop(self.path, IF_P2P, "P2PDeviceConfig",
                                    Variant("a{sv}", {k: Variant(self._sig(v), v) for k, v in cfg.items()}))
            except Exception as e:
                print("could not set P2P device name: %s" % e, file=sys.stderr)

    @staticmethod
    def _sig(v):
        if isinstance(v, bool):
            return "b"
        if isinstance(v, int):
            return "u"
        if isinstance(v, str):
            return "s"
        if isinstance(v, (bytes, bytearray)):
            return "ay"
        if isinstance(v, list):
            return "as" if all(isinstance(x, str) for x in v) else "aay"
        return "s"

    # --- peers -----------------------------------------------------------
    async def load_peer(self, peer_path):
        r = await self.call(peer_path, IF_PROPS, "GetAll", "s", [IF_PEER])
        self.add_peer(unwrap(r.body[0]))

    def add_peer(self, props):
        rec = peer_record(props)
        if rec["address"]:
            old = self.state.peers.get(rec["address"])
            self.state.peers[rec["address"]] = rec
            if old is None or {k: v for k, v in old.items() if k != "last_seen"} != \
                    {k: v for k, v in rec.items() if k != "last_seen"}:
                self.touch()

    def on_message(self, msg):
        from dbus_fast import MessageType
        if msg.message_type != MessageType.SIGNAL or msg.sender is None:
            return
        try:
            self._on_signal(msg)
        except Exception as e:  # never let a bad signal kill the daemon
            print("signal %s failed: %s" % (msg.member, e), file=sys.stderr)

    def _on_signal(self, msg):
        iface, member = msg.interface, msg.member
        if iface == IF_ROOT and member in ("InterfaceAdded", "InterfaceRemoved"):
            if member == "InterfaceRemoved" and msg.body and msg.body[0] == self.path:
                print("wpa interface removed; re-resolving", flush=True)
                self.path = None
                self.state.wpa = "down"
                self.state.peers.clear()
                self.state.scanning = False
                self.state.link = {"state": "idle"}
                self.touch()
            asyncio.ensure_future(self.ensure_attached())
            return
        if msg.path != self.path:
            return
        if iface == IF_P2P:
            if member == "DeviceFoundProperties":
                self.add_peer(unwrap(msg.body[1]))
            elif member == "DeviceLost":
                addr = mac_from_peer_path(msg.body[0])
                if addr and self.state.peers.pop(addr, None):
                    self.touch()
            elif member == "FindStopped":
                if self.want_scan and time.time() < self.state.scan_until:
                    asyncio.ensure_future(self.start_find())
            elif member == "GroupStarted":
                asyncio.ensure_future(self.on_group_started(unwrap(msg.body[0])))
            elif member in ("GONegotiationFailure", "GroupFormationFailure"):
                asyncio.ensure_future(self.retry_connect(member))
            elif member == "GroupFinished" and self.state.link.get("state") == "connecting":
                pass        # a failed attempt being torn down; retry_connect decides what happens next
            elif member == "GroupFinished":
                ifname = self.state.link.get("interface")
                self.state.link = {"state": "idle"}
                self.group_iface_path = None
                self.touch()
                if ifname:
                    asyncio.ensure_future(self.stop_unit(self.args.dhcp_unit % ifname))
                    try:
                        os.unlink(self.lease_path(ifname))
                    except OSError:
                        pass
            elif member == "ProvisionDiscoveryFailure":
                self.state.link = {"state": "error", "reason": member}
                self.touch()

    async def start_unit(self, name):
        await self.call(SYSTEMD_PATH, SYSTEMD_MANAGER, "StartUnit", "ss", [name, "replace"], dest=SYSTEMD)

    async def stop_unit(self, name):
        try:
            await self.call(SYSTEMD_PATH, SYSTEMD_MANAGER, "StopUnit", "ss", [name, "replace"], dest=SYSTEMD)
        except Exception as e:
            print("stopping %s failed: %s" % (name, e), file=sys.stderr)

    def lease_path(self, ifname):
        return os.path.join(os.path.dirname(self.args.state_file), "lease-%s.json" % ifname)

    async def on_group_started(self, info):
        iface_path = info.get("interface_object")
        ifname = None
        if iface_path:
            try:
                ifname = await self.get_prop(iface_path, IF_IFACE, "Ifname")
            except Exception:
                pass
        self.group_iface_path = iface_path
        self.connect_deadline = 0.0
        peer = self.state.link.get("peer")
        self.state.link = {"state": "linked", "role": info.get("role"), "interface": ifname,
                           "group": info.get("group_object"), "peer": peer, "name": self.state.link.get("name")}
        self.touch()
        if ifname and info.get("role") == "client":
            asyncio.ensure_future(self.address_group(ifname))

    async def address_group(self, ifname):
        """Group is up but has no IP: run the DHCP client unit and wait for its lease."""
        try:
            os.unlink(self.lease_path(ifname))
        except OSError:
            pass
        unit = self.args.dhcp_unit % ifname
        try:
            await self.start_unit(unit)
        except Exception as e:
            self.state.link = dict(self.state.link, state="error", reason="cannot start %s: %s" % (unit, e))
            self.touch()
            return
        deadline = time.time() + self.args.dhcp_timeout
        while time.time() < deadline:
            if self.state.link.get("interface") != ifname:     # group went away meanwhile
                return
            try:
                with open(self.lease_path(ifname)) as f:
                    lease = parse_lease(f.read())
            except OSError:
                lease = None
            if lease:
                self.state.link = dict(self.state.link, state="ready", local_ip=lease["ip"],
                                       mask=lease["mask"], remote_ip=lease["router"],
                                       rtsp_port=self.args.rtsp_port)
                self.touch()
                return
            await asyncio.sleep(0.5)
        self.state.link = dict(self.state.link, state="error", reason="no DHCP lease from the TV")
        self.touch()

    # --- scanning --------------------------------------------------------
    async def start_find(self):
        from dbus_fast import Variant
        if not self.path:
            return
        try:
            await self.call(self.path, IF_P2P, "Find", "a{sv}", [{"Timeout": Variant("i", 30)}])
            self.state.scanning = True
        except Exception as e:
            self.state.error = str(e)
            self.state.scanning = False
        self.touch()

    async def stop_find(self):
        self.want_scan = False
        self.state.scanning = False
        if self.path:
            try:
                await self.call(self.path, IF_P2P, "StopFind")
            except Exception:
                pass
        self.touch()

    # --- control ---------------------------------------------------------
    async def handle(self, req):
        cmd = req.get("cmd")
        if cmd == "status":
            return {"ok": True, "state": self.state.to_json()}
        if self.path is None and cmd in ("scan", "connect", "flush"):
            return {"ok": False, "error": "wpa_supplicant interface not available"}
        if cmd == "scan":
            if req.get("on", True) and self.state.link.get("state") in ("connecting", "linked", "ready"):
                return {"ok": False, "error": "a link is %s; disconnect first" % self.state.link["state"]}
            if req.get("on", True):
                secs = int(req.get("seconds", self.args.scan_seconds))
                self.want_scan = True
                self.state.scan_until = time.time() + secs
                await self.start_find()
                return {"ok": True, "scanning": self.state.scanning}
            if self.state.link.get("state") in ("connecting", "linked", "ready"):
                self.want_scan = False
                self.state.scanning = False
                self.touch()
                return {"ok": True, "scanning": False, "note": "link active; not stopping wpa's find"}
            await self.stop_find()
            return {"ok": True, "scanning": False}
        if cmd == "flush":
            await self.call(self.path, IF_P2P, "Flush")
            self.state.peers.clear()
            self.touch()
            return {"ok": True}
        if cmd == "connect":
            return await self.connect(req)
        if cmd == "disconnect":
            if self.path:
                try:
                    await self.call(self.path, IF_P2P, "Disconnect")
                except Exception as e:
                    return {"ok": False, "error": str(e)}
            ifname = self.state.link.get("interface")
            self.state.link = {"state": "idle"}
            self.touch()
            if ifname:
                await self.stop_unit(self.args.dhcp_unit % ifname)
            return {"ok": True}
        return {"ok": False, "error": "unknown cmd %r" % cmd}

    async def connect(self, req):
        addr = (req.get("address") or "").lower().replace("-", ":")
        peer = self.state.peers.get(addr)
        if not peer:
            return {"ok": False, "error": "no such peer %s (scan first)" % addr}
        # wpa_supplicant turns the search into the negotiation by itself. Our own
        # scan timer must not call StopFind from here on: that cancels a pending
        # connection ("Removing pending group interface").
        self.want_scan = False
        self.state.scanning = False
        self.connect_addr = addr
        self.connect_args = req
        self.connect_attempt = 1
        self.state.link = {"state": "connecting", "peer": addr, "name": peer["name"], "attempt": 1}
        err = await self.do_connect()
        if err:
            return {"ok": False, "error": err}
        return {"ok": True, "link": self.state.link}

    async def do_connect(self):
        """One P2P Connect call. Returns an error string, or None."""
        from dbus_fast import Variant
        req = self.connect_args or {}
        peer_path = "%s/Peers/%s" % (self.path, self.connect_addr.replace(":", ""))
        args = {
            "peer": Variant("o", peer_path),
            "wps_method": Variant("s", req.get("wps", "pbc")),
            "go_intent": Variant("i", int(req.get("go_intent", 0))),
            "persistent": Variant("b", False),
            "join": Variant("b", False),
        }
        self.connect_deadline = time.time() + self.args.connect_timeout
        self.touch()
        try:
            await self.call(self.path, IF_P2P, "Connect", "a{sv}", [args])
        except Exception as e:
            self.state.link = {"state": "error", "reason": str(e)}
            self.touch()
            return str(e)
        return None

    async def retry_connect(self, why):
        """A formation or negotiation attempt failed: try again a few times.
        The TV sometimes drops the last step of group formation (an EAP failure
        right after WPS succeeds), and succeeds on the next go."""
        if not self.connect_addr or self.state.link.get("state") != "connecting":
            return
        if self.connect_attempt >= self.args.connect_retries:
            self.state.link = {"state": "error", "peer": self.connect_addr,
                               "reason": "gave up after %d attempts (%s)" % (self.connect_attempt, why)}
            self.touch()
            return
        self.connect_attempt += 1
        attempt = self.connect_attempt
        self.state.link = dict(self.state.link, attempt=attempt, last_failure=why)
        self.touch()
        print("connect attempt %d failed (%s); retrying as attempt %d" % (attempt - 1, why, attempt), flush=True)
        await asyncio.sleep(2.0)
        if self.connect_attempt != attempt or self.state.link.get("state") != "connecting":
            return
        # the peer is dropped when a group fails: look for the TV again first
        if self.connect_addr not in self.state.peers:
            await self.start_find()
            end = time.time() + 12
            while time.time() < end and self.connect_addr not in self.state.peers:
                await asyncio.sleep(0.5)
            if self.connect_addr not in self.state.peers:
                self.state.link = {"state": "error", "peer": self.connect_addr,
                                   "reason": "the TV disappeared while retrying (still on Display Mirroring?)"}
                self.touch()
                return
        self.want_scan = False
        self.state.scanning = False
        await self.do_connect()

    async def client(self, reader, writer):
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    reply = await self.handle(json.loads(line))
                except Exception as e:
                    reply = {"ok": False, "error": str(e)}
                writer.write((json.dumps(reply) + "\n").encode())
                await writer.drain()
        finally:
            writer.close()

    # --- housekeeping ----------------------------------------------------
    def touch(self):
        self.dirty.set()

    async def publisher(self):
        """Write state.json at most once a second, and tick timers."""
        while True:
            try:
                await asyncio.wait_for(self.dirty.wait(), timeout=1.0)
            except asyncio.TimeoutError:
                pass
            self.dirty.clear()
            now = time.time()
            if self.state.expire(now):
                pass
            if self.state.link.get("state") == "connecting" and now >= self.connect_deadline:
                self.state.link = {"state": "error", "reason": "timed out waiting for the TV"}
            if self.state.scanning and now >= self.state.scan_until \
                    and self.state.link.get("state") not in ("connecting", "linked", "ready"):
                self.want_scan = False
                self.state.scanning = False
                if self.path:
                    try:
                        await self.call(self.path, IF_P2P, "StopFind")
                    except Exception:
                        pass
            try:
                write_atomic(self.args.state_file, self.state.to_json(now))
            except OSError as e:
                print("cannot write state: %s" % e, file=sys.stderr)
            await asyncio.sleep(1.0)

    async def ensure_attached(self):
        if self.path is not None:
            return
        try:
            await self.attach()
        except Exception as e:
            self.state.wpa = "down"
            self.state.error = str(e)

    async def watchdog(self):
        """wpa_supplicant (re)starts come and go; keep trying to attach."""
        while True:
            if self.path is None:
                await self.ensure_attached()
                self.touch()
            await asyncio.sleep(3.0)

    async def run(self):
        from dbus_fast import BusType
        from dbus_fast.aio import MessageBus
        os.makedirs(os.path.dirname(self.args.state_file), exist_ok=True)
        bus_type = BusType.SESSION if self.args.bus == "session" else BusType.SYSTEM
        self.bus = await MessageBus(bus_type=bus_type).connect()
        self.bus.add_message_handler(self.on_message)
        await self.add_match("type='signal',sender='%s'" % WPA_NAME)

        sock = self.args.socket
        if os.path.exists(sock):
            os.unlink(sock)
        server = await asyncio.start_unix_server(self.client, path=sock)
        os.chmod(sock, 0o660)
        try:
            # -1 keeps the owner; only the group changes (works unprivileged in tests)
            os.chown(sock, -1, grp.getgrnam(self.args.group).gr_gid)
        except KeyError:
            print("group %r not found; socket stays owner-only" % self.args.group, file=sys.stderr)
        except OSError as e:
            print("cannot set socket group %r: %s" % (self.args.group, e), file=sys.stderr)

        loop = asyncio.get_running_loop()
        stop = loop.create_future()
        for s in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(s, lambda: stop.done() or stop.set_result(None))
        tasks = [asyncio.ensure_future(self.publisher()), asyncio.ensure_future(self.watchdog())]
        print("miracast-linkd ready (state %s, socket %s)" % (self.args.state_file, sock), flush=True)
        await stop
        for t in tasks:
            t.cancel()
        server.close()
        try:
            os.unlink(sock)
        except OSError:
            pass


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--interface", default=None, help="wpa_supplicant interface name (default: auto)")
    p.add_argument("--state-file", default="/run/miracast/state.json")
    p.add_argument("--socket", default="/run/miracast/linkd.sock")
    p.add_argument("--group", default="users", help="group allowed to use the control socket")
    p.add_argument("--peer-ttl", type=float, default=120.0, help="seconds before an unseen peer is dropped")
    p.add_argument("--scan-seconds", type=int, default=60, help="default scan duration")
    p.add_argument("--dhcp-unit", default="miracast-dhcp@%s.service",
                   help="systemd unit (template) that runs the DHCP client for a group interface; %%s = interface")
    p.add_argument("--dhcp-timeout", type=int, default=20, help="seconds to wait for a lease")
    p.add_argument("--connect-retries", type=int, default=3, help="attempts before giving up on a connection")
    p.add_argument("--connect-timeout", type=int, default=60, help="seconds to wait for a group to form")
    p.add_argument("--rtsp-port", type=int, default=7236, help="RTSP port advertised in the WFD IE")
    p.add_argument("--throughput", type=int, default=50, help="max throughput advertised (Mbit/s)")
    p.add_argument("--bus", choices=["system", "session"], default="system",
                   help="D-Bus to use (session is for tests against a mock wpa_supplicant)")
    p.add_argument("--device-name", default=None, help="P2P device name shown to the TV")
    args = p.parse_args(argv)
    asyncio.run(Daemon(args).run())


if __name__ == "__main__":
    main()

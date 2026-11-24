#!/usr/bin/env python3
"""coel-bt-agent: a BlueZ pairing agent that hands its questions to a UI.

BlueZ asks a registered *agent* (org.bluez.Agent1) whenever pairing needs a
decision: compare a 6-digit passkey, type a PIN, authorize a connection. The
old agent here (`bluetoothctl --agent NoInputNoOutput`) answered "yes" to
everything and could not do passkeys or PINs at all. This one registers as
KeyboardDisplay (the capability that supports all of it) and forwards each
question over a unix socket as JSON lines, so the Quickshell bluetooth
dropdown can show it and send the answer back.

  socket   $XDG_RUNTIME_DIR/coel-bt-agent.sock   (0600, one JSON object per line)

  agent -> client
    {"event":"hello","version":2}     (version 1 had no pair/connect commands)
    {"event":"request","id":N,"kind":"confirm|pincode|passkey|authorize|service",
     "device":{"path","name","address","icon"},"passkey":482913,"uuid":"...","timeout":30}
        the client must answer, or the request times out and is rejected
    {"event":"display","kind":"passkey|pin","device":{...},"passkey":482913,"entered":3}
        show this code while the user types it on the *device*; repeated as digits arrive
    {"event":"cancel","id":N,"reason":"cancelled|timeout"}   a request is no longer wanted
    {"event":"clear"}                                          drop any displayed code
    {"event":"paired","device":{...},"paired":true|false}      a device's Paired flag changed

    {"event":"status","op":"pair|connect|disconnect","address":"AA:..","step":S,"error":"org.bluez.Error.X","reason":"..."}
        progress of a command the client sent. step: linking (reaching the device) | linked (link is up) |
        resolved (services discovered) | done | failed. On failed, `reason` is human-readable and `error` is
        BlueZ's own error name, so the UI can show *why* instead of a generic failure.

  client -> agent
    {"cmd":"pair","address":"AA:.."}                           start pairing (BlueZ Pair(), 60s limit)
    {"cmd":"connect","address":"AA:.."}                        connect a paired device (45s limit)
    {"cmd":"disconnect","address":"AA:.."}
    {"cmd":"cancel","address":"AA:.."}                         abort a pair (CancelPairing) / connect (Disconnect)
    {"cmd":"reply","id":N,"accept":true}                       confirm / authorize / service
    {"cmd":"reply","id":N,"accept":true,"value":"1234"}        pincode (string) / passkey (number)
    {"cmd":"reply","id":N,"accept":false}                      reject

With **no client connected** it behaves like the old agent so nothing regresses:
confirmations and authorizations are accepted (Just Works pairing), requests
that need typed input (PIN / passkey) are rejected. A paired or trusted device
reconnecting is never asked about its services, UI or not.
"""

import asyncio
import json
import logging
import os
import signal
import sys

from dbus_fast import BusType, DBusError, Message, MessageType, Variant
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, method

log = logging.getLogger("coel-bt-agent")

AGENT_PATH = "/org/coel/BluetoothAgent"
CAPABILITY = "KeyboardDisplay"
BLUEZ = "org.bluez"
REQUEST_TIMEOUT = 30.0
PROTOCOL_VERSION = 2          # 2: pair / connect / disconnect / cancel commands and "status" events


def socket_path():
    return os.environ.get("COEL_BT_AGENT_SOCKET") or os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "coel-bt-agent.sock")


class Rejected(Exception):
    pass


class Broker:
    """Tracks UI clients and the requests waiting on them (no D-Bus in here, so it is unit-testable)."""

    def __init__(self, timeout=REQUEST_TIMEOUT):
        self.timeout = timeout
        self.clients = set()          # asyncio.StreamWriter
        self.pending = {}             # id -> (Future, event dict)
        self.displayed = {}           # device path -> display event (replayed to late clients)
        self.command_handler = None   # async callable(msg) for {"cmd": ...} other than "reply"
        self._next = 1

    # ---- output ----
    def send(self, writer, obj):
        try:
            writer.write((json.dumps(obj) + "\n").encode())
        except Exception:             # a dead client is dropped by its own read loop
            pass

    def broadcast(self, obj):
        for w in list(self.clients):
            self.send(w, obj)

    @property
    def has_client(self):
        return bool(self.clients)

    # ---- requests ----
    async def ask(self, kind, device, **extra):
        """Ask the UI; returns the reply dict ({'accept': bool, 'value': ...}). Raises Rejected on timeout."""
        rid = self._next
        self._next += 1
        ev = {"event": "request", "id": rid, "kind": kind, "device": device, "timeout": self.timeout, **extra}
        fut = asyncio.get_running_loop().create_future()
        self.pending[rid] = (fut, ev)
        self.broadcast(ev)
        try:
            return await asyncio.wait_for(fut, self.timeout)
        except asyncio.TimeoutError:
            self.broadcast({"event": "cancel", "id": rid, "reason": "timeout"})
            raise Rejected("timed out waiting for the UI")
        finally:
            self.pending.pop(rid, None)

    def reply(self, rid, accept, value=None):
        item = self.pending.get(rid)
        if item and not item[0].done():
            item[0].set_result({"accept": bool(accept), "value": value})
            return True
        return False

    def cancel_all(self, reason="cancelled"):
        for rid, (fut, _ev) in list(self.pending.items()):
            if not fut.done():
                fut.set_exception(Rejected(reason))
            self.broadcast({"event": "cancel", "id": rid, "reason": reason})
        self.clear_display()

    # ---- displayed codes ----
    def show(self, kind, device, **extra):
        ev = {"event": "display", "kind": kind, "device": device, **extra}
        self.displayed[device["path"]] = ev
        self.broadcast(ev)

    def clear_display(self):
        if self.displayed:
            self.displayed.clear()
            self.broadcast({"event": "clear"})

    # ---- clients ----
    async def serve_client(self, reader, writer):
        self.clients.add(writer)
        self.send(writer, {"event": "hello", "version": PROTOCOL_VERSION})
        for _fut, ev in self.pending.values():       # a UI opened mid-request still sees it
            self.send(writer, ev)
        for ev in self.displayed.values():
            self.send(writer, ev)
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if isinstance(msg, dict) and msg.get("cmd") == "reply" and isinstance(msg.get("id"), int):
                    self.reply(msg["id"], msg.get("accept", False), msg.get("value"))
                elif isinstance(msg, dict) and self.command_handler and msg.get("cmd") in ("pair", "connect", "disconnect", "cancel"):
                    asyncio.ensure_future(self.command_handler(msg))
        except (ConnectionError, asyncio.CancelledError):
            pass
        finally:
            self.clients.discard(writer)
            try:
                writer.close()
            except Exception:
                pass


FRIENDLY = {
    "org.bluez.Error.AuthenticationCanceled": "pairing was cancelled",
    "org.bluez.Error.AuthenticationFailed": "authentication failed -- wrong PIN/passkey, or the device refused",
    "org.bluez.Error.AuthenticationRejected": "the device rejected pairing",
    "org.bluez.Error.AuthenticationTimeout": "timed out waiting for the device -- keep its Bluetooth settings screen open and try again",
    "org.bluez.Error.ConnectionAttemptFailed": "could not reach the device -- is it on, in range and discoverable?",
    "org.bluez.Error.AlreadyExists": "already paired",
    "org.bluez.Error.AlreadyConnected": "already connected",
    "org.bluez.Error.InProgress": "another pairing or connection is already in progress",
    "org.bluez.Error.NotReady": "the Bluetooth adapter is not ready",
    "org.bluez.Error.NotAvailable": "the device does not offer a usable service",
    "org.bluez.Error.DoesNotExist": "the device is no longer known -- rescan and try again",
}
MESSAGE_HINTS = (                       # org.bluez.Error.Failed carries the real cause only in its message text
    ("page-timeout", "the device did not answer (page timeout) -- is it on, in range and discoverable?"),
    ("page timeout", "the device did not answer (page timeout) -- is it on, in range and discoverable?"),
    ("connection-failed", "the connection failed"),
    ("profile-unavailable", "the device has no profile we can connect to"),
    ("authentication", "authentication failed"),
    ("le-connection-abort-by-local", "the connection was aborted"),
)


def friendly_error(name, message=""):
    """Human-readable reason for a BlueZ error (name = D-Bus error name, message = its text)."""
    if name in FRIENDLY:
        return FRIENDLY[name]
    low = (message or "").lower()
    for needle, text in MESSAGE_HINTS:
        if needle in low:
            return text
    return (message or name or "failed").strip()


class Ops:
    """pair / connect / disconnect run on behalf of a UI client, with step events and real error reasons."""

    LIMITS = {"pair": 60.0, "connect": 45.0, "disconnect": 15.0}

    def __init__(self, bus, broker):
        self.bus = bus
        self.broker = broker
        self.active = {}              # address -> (op, path, task)

    def emit(self, op, address, step, **extra):
        self.broker.broadcast({"event": "status", "op": op, "address": address, "step": step, **extra})

    async def find_path(self, address):
        reply = await self.bus.call(Message(destination=BLUEZ, path="/", interface="org.freedesktop.DBus.ObjectManager",
                                            member="GetManagedObjects"))
        if reply.message_type != MessageType.METHOD_RETURN:
            return None
        for path, ifaces in reply.body[0].items():
            dev = ifaces.get("org.bluez.Device1")
            if dev and str(dev.get("Address").value).upper() == address.upper():
                return path
        return None

    async def device_call(self, path, member):
        return await self.bus.call(Message(destination=BLUEZ, path=path, interface="org.bluez.Device1", member=member))

    def start(self, op, address):
        if address in self.active:
            self.emit(op, address, "failed", error="org.bluez.Error.InProgress", reason=FRIENDLY["org.bluez.Error.InProgress"])
            return
        task = asyncio.ensure_future(self.run(op, address))
        self.active[address] = (op, None, task)

    async def run(self, op, address):
        try:
            path = await self.find_path(address)
            if not path:
                self.emit(op, address, "failed", error="org.bluez.Error.DoesNotExist", reason=FRIENDLY["org.bluez.Error.DoesNotExist"])
                return
            self.active[address] = (op, path, self.active[address][2])
            self.emit(op, address, "linking")
            member = {"pair": "Pair", "connect": "Connect", "disconnect": "Disconnect"}[op]
            try:
                reply = await asyncio.wait_for(self.device_call(path, member), self.LIMITS[op])
            except asyncio.TimeoutError:
                if op == "pair":
                    await self.device_call(path, "CancelPairing")
                self.emit(op, address, "failed", error="timeout", reason="timed out after %ds -- the device never answered" % int(self.LIMITS[op]))
                return
            if reply.message_type == MessageType.ERROR:
                text = reply.body[0] if reply.body else ""
                self.emit(op, address, "failed", error=reply.error_name, reason=friendly_error(reply.error_name, text), detail=str(text))
                log.info("%s %s failed: %s %s", op, address, reply.error_name, text)
            else:
                self.emit(op, address, "done")
        except asyncio.CancelledError:
            raise
        except Exception as e:
            log.exception("%s %s crashed", op, address)
            self.emit(op, address, "failed", error="internal", reason=str(e))
        finally:
            self.active.pop(address, None)

    async def cancel(self, address):
        item = self.active.get(address)
        if not item:
            return
        op, path, task = item
        if path:
            await self.device_call(path, "CancelPairing" if op == "pair" else "Disconnect")
        task.cancel()
        self.active.pop(address, None)
        self.emit(op, address, "failed", error="cancelled", reason="cancelled")

    def device_props_changed(self, address, changed):
        """Intermediate steps while an op is in flight (from the Device1 PropertiesChanged signal)."""
        item = self.active.get(address)
        if not item:
            return
        op = item[0]
        if "Connected" in changed and changed["Connected"].value:
            self.emit(op, address, "linked")
        if "ServicesResolved" in changed and changed["ServicesResolved"].value:
            self.emit(op, address, "resolved")

    async def handle_command(self, msg):
        cmd, address = msg.get("cmd"), str(msg.get("address") or "")
        if cmd in ("pair", "connect", "disconnect") and address:
            self.start(cmd, address)
        elif cmd == "cancel" and address:
            await self.cancel(address)


def reject(msg="rejected"):
    return DBusError("org.bluez.Error.Rejected", msg)


class Agent(ServiceInterface):
    def __init__(self, bus, broker):
        super().__init__("org.bluez.Agent1")
        self.bus = bus
        self.broker = broker

    async def device_info(self, path):
        info = {"path": path, "name": path.rsplit("/", 1)[-1].replace("dev_", "").replace("_", ":"), "address": "", "icon": "",
                "paired": False, "trusted": False}
        try:
            reply = await self.bus.call(Message(destination=BLUEZ, path=path, interface="org.freedesktop.DBus.Properties",
                                                member="GetAll", signature="s", body=["org.bluez.Device1"]))
            if reply.message_type == MessageType.METHOD_RETURN:
                p = {k: v.value for k, v in reply.body[0].items()}
                info.update(name=p.get("Alias") or p.get("Name") or info["name"], address=p.get("Address", ""),
                            icon=p.get("Icon", ""), paired=bool(p.get("Paired")), trusted=bool(p.get("Trusted")))
        except Exception as e:
            log.debug("could not read %s: %s", path, e)
        return info

    async def _decide(self, kind, path, default_accept, **extra):
        """Ask the UI when there is one, otherwise fall back to `default_accept`. Returns the reply dict."""
        dev = await self.device_info(path)
        log.info("bluez asks: %s for %s (%s)%s", kind, dev["name"], dev["address"], " -> UI" if self.broker.has_client else "")
        if not self.broker.has_client:
            log.info("%s from %s (%s): no UI connected -> %s", kind, dev["name"], dev["address"], "accept" if default_accept else "reject")
            return dev, {"accept": default_accept, "value": None}
        try:
            return dev, await self.broker.ask(kind, dev, **extra)
        except Rejected as e:
            raise reject(str(e))

    @method()
    def Release(self):
        log.info("released by bluetoothd")
        self.broker.cancel_all("released")

    @method()
    async def RequestConfirmation(self, device: "o", passkey: "u"):
        _dev, r = await self._decide("confirm", device, True, passkey=int(passkey))
        if not r["accept"]:
            raise reject()

    @method()
    async def RequestAuthorization(self, device: "o"):
        _dev, r = await self._decide("authorize", device, True)
        if not r["accept"]:
            raise reject()

    @method()
    async def AuthorizeService(self, device: "o", uuid: "s"):
        dev = await self.device_info(device)
        if dev["paired"] or dev["trusted"]:        # a known device reconnecting: do not nag
            return
        _dev, r = await self._decide("service", device, True, uuid=str(uuid))
        if not r["accept"]:
            raise reject()

    @method()
    async def RequestPinCode(self, device: "o") -> "s":
        _dev, r = await self._decide("pincode", device, False)
        if not r["accept"] or not str(r.get("value") or "").strip():
            raise reject()
        return str(r["value"]).strip()[:16]

    @method()
    async def RequestPasskey(self, device: "o") -> "u":
        _dev, r = await self._decide("passkey", device, False)
        digits = "".join(c for c in str(r.get("value") or "") if c.isdigit())
        if not r["accept"] or not digits:
            raise reject()
        return min(int(digits), 999999)

    @method()
    async def DisplayPasskey(self, device: "o", passkey: "u", entered: "q"):
        self.broker.show("passkey", await self.device_info(device), passkey=int(passkey), entered=int(entered))

    @method()
    async def DisplayPinCode(self, device: "o", pincode: "s"):
        self.broker.show("pin", await self.device_info(device), passkey=str(pincode), entered=0)

    @method()
    def Cancel(self):
        log.info("pairing cancelled by bluetoothd")
        self.broker.cancel_all("cancelled")


async def handle_device_props(agent, broker, ops, path, changed):
    """Device1 PropertiesChanged: progress for running ops, and "paired" events for everyone."""
    # Progress first and without awaiting anything: the signal has to be turned into a step event before
    # the Pair()/Connect() reply that ends the op is processed.
    name = path.rsplit("/", 1)[-1]
    if name.startswith("dev_"):
        ops.device_props_changed(name[4:].replace("_", ":"), changed)
    if "Paired" in changed:
        dev = await agent.device_info(path)
        dev["paired"] = bool(changed["Paired"].value)
        broker.broadcast({"event": "paired", "device": dev, "paired": dev["paired"]})
        if dev["paired"]:
            broker.clear_display()


async def call_manager(bus, member, signature, body):
    reply = await bus.call(Message(destination=BLUEZ, path="/org/bluez", interface="org.bluez.AgentManager1",
                                   member=member, signature=signature, body=body))
    if reply.message_type == MessageType.ERROR:
        raise RuntimeError("%s: %s" % (reply.error_name, reply.body[0] if reply.body else ""))


async def register(bus):
    await call_manager(bus, "RegisterAgent", "os", [AGENT_PATH, CAPABILITY])
    await call_manager(bus, "RequestDefaultAgent", "o", [AGENT_PATH])
    log.info("registered as the default agent (%s)", CAPABILITY)


async def register_with_retry(bus, attempts=30):
    for i in range(attempts):
        try:
            await register(bus)
            return True
        except Exception as e:
            log.warning("register failed (%s); retrying", e)
            await asyncio.sleep(2)
    return False


async def main():
    logging.basicConfig(level=os.environ.get("COEL_BT_AGENT_LOG", "INFO"), format="%(name)s: %(message)s")
    bus_type = BusType.SESSION if os.environ.get("COEL_BT_AGENT_BUS") == "session" else BusType.SYSTEM
    bus = await MessageBus(bus_type=bus_type).connect()
    broker = Broker()
    agent = Agent(bus, broker)
    ops = Ops(bus, broker)
    broker.command_handler = ops.handle_command
    bus.export(AGENT_PATH, agent)

    # paired-flag changes -> "paired" events, and re-register when bluetoothd restarts.
    async def on_message(msg):
        if msg.message_type != MessageType.SIGNAL:
            return
        if msg.interface == "org.freedesktop.DBus.Properties" and msg.member == "PropertiesChanged" and msg.body[0] == "org.bluez.Device1":
            await handle_device_props(agent, broker, ops, msg.path, msg.body[1])
        elif msg.interface == "org.freedesktop.DBus" and msg.member == "NameOwnerChanged" and msg.body[0] == BLUEZ and msg.body[2]:
            log.info("bluetoothd (re)started")
            await register_with_retry(bus)

    bus.add_message_handler(lambda m: asyncio.ensure_future(on_message(m)) and None)
    for rule in ("type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'",
                 "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='%s'" % BLUEZ):
        await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus", interface="org.freedesktop.DBus",
                               member="AddMatch", signature="s", body=[rule]))

    path = socket_path()
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    server = await asyncio.start_unix_server(broker.serve_client, path=path)
    os.chmod(path, 0o600)
    log.info("listening on %s", path)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    await register_with_retry(bus)
    await stop.wait()
    try:
        await call_manager(bus, "UnregisterAgent", "o", [AGENT_PATH])
    except Exception:
        pass
    server.close()
    try:
        os.unlink(path)
    except OSError:
        pass
    bus.disconnect()


if __name__ == "__main__":
    asyncio.run(main())

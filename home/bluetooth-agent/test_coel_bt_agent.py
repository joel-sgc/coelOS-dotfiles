"""Tests for coel_bt_agent against a private session bus with a fake bluetoothd.

Run (needs dbus-daemon and dbus-fast):
  nix-shell -p dbus python3Packages.dbus-fast --run 'python3 test_coel_bt_agent.py'
"""

import asyncio
import json
import os
import shutil
import subprocess
import tempfile
import unittest

from dbus_fast import DBusError, Message, MessageType
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, dbus_property, method
from dbus_fast.constants import PropertyAccess

import coel_bt_agent as agent_mod

DEV = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
KNOWN = "/org/bluez/hci0/dev_11_22_33_44_55_66"


class FakeManager(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.AgentManager1")
        self.calls = []

    @method()
    def RegisterAgent(self, agent: "o", capability: "s"):
        self.calls.append(("RegisterAgent", agent, capability))

    @method()
    def RequestDefaultAgent(self, agent: "o"):
        self.calls.append(("RequestDefaultAgent", agent))

    @method()
    def UnregisterAgent(self, agent: "o"):
        self.calls.append(("UnregisterAgent", agent))


class FakeDevice(ServiceInterface):
    def __init__(self, alias, address, paired=False, trusted=False):
        super().__init__("org.bluez.Device1")
        self.v = (alias, address, paired, trusted)
        self.fail = None            # (error name, message) for the next Pair/Connect
        self.hang = False           # Pair/Connect never returns until cancelled
        self.calls = []

    async def _op(self, name, props=None):
        self.calls.append(name)
        if props:
            self.emit_properties_changed(props)
        if self.hang:
            await asyncio.sleep(30)
        if self.fail:
            raise DBusError(*self.fail)

    @method()
    async def Pair(self):
        await self._op("Pair")

    @method()
    async def Connect(self):
        await self._op("Connect", {"Connected": True})
        self.emit_properties_changed({"ServicesResolved": True})

    @method()
    async def Disconnect(self):
        self.calls.append("Disconnect")

    @method()
    def CancelPairing(self):
        self.calls.append("CancelPairing")
        self.hang = False

    @dbus_property(access=PropertyAccess.READ)
    def ServicesResolved(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Connected(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Alias(self) -> "s":
        return self.v[0]

    @dbus_property(access=PropertyAccess.READ)
    def Address(self) -> "s":
        return self.v[1]

    @dbus_property(access=PropertyAccess.READ)
    def Paired(self) -> "b":
        return self.v[2]

    @dbus_property(access=PropertyAccess.READ)
    def Trusted(self) -> "b":
        return self.v[3]


class Client:
    """A UI on the agent's unix socket."""

    def __init__(self, path):
        self.path = path
        self.events = asyncio.Queue()

    async def connect(self):
        self.reader, self.writer = await asyncio.open_unix_connection(self.path)
        self.task = asyncio.ensure_future(self._read())
        hello = await self.next()
        assert hello["event"] == "hello", hello

    async def _read(self):
        while True:
            line = await self.reader.readline()
            if not line:
                return
            await self.events.put(json.loads(line))

    async def next(self, timeout=3):
        return await asyncio.wait_for(self.events.get(), timeout)

    def command(self, cmd, address="AA:BB:CC:DD:EE:FF"):
        self.writer.write((json.dumps({"cmd": cmd, "address": address}) + "\n").encode())

    async def statuses(self, until=("done", "failed")):
        out = []
        while True:
            ev = await self.next()
            if ev["event"] == "status":
                out.append(ev)
                if ev["step"] in until:
                    return out

    def reply(self, rid, accept, value=None):
        self.writer.write((json.dumps({"cmd": "reply", "id": rid, "accept": accept, "value": value}) + "\n").encode())

    async def close(self):
        self.task.cancel()
        self.writer.close()


class AgentTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.mkdtemp()
        conf = os.path.join(self.tmp, "bus.conf")
        with open(conf, "w") as f:
            f.write("""<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=%s/bus</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>""" % self.tmp)
        self.daemon = subprocess.Popen(["dbus-daemon", "--config-file=" + conf, "--nofork", "--print-address=1"],
                                       stdout=subprocess.PIPE, text=True)
        self.addr = self.daemon.stdout.readline().strip()
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = self.addr

        self.bluez = await MessageBus(bus_address=self.addr).connect()
        self.manager = FakeManager()
        self.bluez.export("/org/bluez", self.manager)
        self.dev = FakeDevice("Test Headset", "AA:BB:CC:DD:EE:FF")
        self.bluez.export(DEV, self.dev)
        self.bluez.export(KNOWN, FakeDevice("Known Mouse", "11:22:33:44:55:66", paired=True))
        await self.bluez.request_name("org.bluez")

        self.agent_bus = await MessageBus(bus_address=self.addr).connect()
        self.broker = agent_mod.Broker(timeout=1.0)
        self.agent = agent_mod.Agent(self.agent_bus, self.broker)
        self.agent_bus.export(agent_mod.AGENT_PATH, self.agent)
        self.ops = agent_mod.Ops(self.agent_bus, self.broker)
        self.broker.command_handler = self.ops.handle_command

        async def on_msg(msg):
            if msg.message_type == MessageType.SIGNAL and msg.member == "PropertiesChanged" and msg.body[0] == "org.bluez.Device1":
                await agent_mod.handle_device_props(self.agent, self.broker, self.ops, msg.path, msg.body[1])
        self.agent_bus.add_message_handler(lambda m: asyncio.ensure_future(on_msg(m)) and None)
        await self.agent_bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus", interface="org.freedesktop.DBus",
                                          member="AddMatch", signature="s",
                                          body=["type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'"]))
        self.sock = os.path.join(self.tmp, "agent.sock")
        self.server = await asyncio.start_unix_server(self.broker.serve_client, path=self.sock)

        self.caller = await MessageBus(bus_address=self.addr).connect()

    async def asyncTearDown(self):
        for b in (self.caller, self.agent_bus, self.bluez):
            b.disconnect()
        self.server.close()
        self.daemon.terminate()
        self.daemon.wait()
        shutil.rmtree(self.tmp, ignore_errors=True)

    async def call(self, member, signature="", body=None):
        return await self.caller.call(Message(destination=self.agent_bus.unique_name, path=agent_mod.AGENT_PATH,
                                              interface="org.bluez.Agent1", member=member, signature=signature, body=body or []))

    # ---- registration ----
    async def test_registers_as_keyboard_display_default(self):
        await agent_mod.register(self.agent_bus)
        self.assertEqual(self.manager.calls, [("RegisterAgent", agent_mod.AGENT_PATH, "KeyboardDisplay"),
                                              ("RequestDefaultAgent", agent_mod.AGENT_PATH)])

    # ---- with a UI ----
    async def test_confirm_accepted_by_ui(self):
        ui = Client(self.sock); await ui.connect()
        pending = asyncio.ensure_future(self.call("RequestConfirmation", "ou", [DEV, 482913]))
        ev = await ui.next()
        self.assertEqual((ev["event"], ev["kind"], ev["passkey"]), ("request", "confirm", 482913))
        self.assertEqual(ev["device"]["name"], "Test Headset")
        self.assertEqual(ev["device"]["address"], "AA:BB:CC:DD:EE:FF")
        ui.reply(ev["id"], True)
        self.assertEqual((await pending).message_type, MessageType.METHOD_RETURN)
        await ui.close()

    async def test_confirm_rejected_by_ui(self):
        ui = Client(self.sock); await ui.connect()
        pending = asyncio.ensure_future(self.call("RequestConfirmation", "ou", [DEV, 1]))
        ev = await ui.next()
        ui.reply(ev["id"], False)
        r = await pending
        self.assertEqual((r.message_type, r.error_name), (MessageType.ERROR, "org.bluez.Error.Rejected"))
        await ui.close()

    async def test_passkey_and_pin_values(self):
        ui = Client(self.sock); await ui.connect()
        p = asyncio.ensure_future(self.call("RequestPasskey", "o", [DEV]))
        ev = await ui.next(); self.assertEqual(ev["kind"], "passkey")
        ui.reply(ev["id"], True, "004 821")
        self.assertEqual((await p).body, [4821])
        p = asyncio.ensure_future(self.call("RequestPinCode", "o", [DEV]))
        ev = await ui.next(); self.assertEqual(ev["kind"], "pincode")
        ui.reply(ev["id"], True, " 0000 ")
        self.assertEqual((await p).body, ["0000"])
        await ui.close()

    async def test_unanswered_request_times_out_as_rejected(self):
        ui = Client(self.sock); await ui.connect()
        r = await self.call("RequestConfirmation", "ou", [DEV, 5])
        self.assertEqual(r.error_name, "org.bluez.Error.Rejected")
        ev = await ui.next(); self.assertEqual(ev["event"], "request")
        ev = await ui.next(); self.assertEqual((ev["event"], ev["reason"]), ("cancel", "timeout"))
        await ui.close()

    async def test_display_passkey_is_forwarded_and_replayed(self):
        ui = Client(self.sock); await ui.connect()
        await self.call("DisplayPasskey", "ouq", [DEV, 123456, 2])
        ev = await ui.next()
        self.assertEqual((ev["event"], ev["kind"], ev["passkey"], ev["entered"]), ("display", "passkey", 123456, 2))
        late = Client(self.sock); await late.connect()            # opened mid-pairing: sees the code too
        self.assertEqual((await late.next())["passkey"], 123456)
        await self.call("Cancel")
        self.assertEqual((await ui.next())["event"], "clear")
        await ui.close(); await late.close()

    async def test_known_device_service_authorization_is_silent(self):
        ui = Client(self.sock); await ui.connect()
        r = await self.call("AuthorizeService", "os", [KNOWN, "0000110b-0000-1000-8000-00805f9b34fb"])
        self.assertEqual(r.message_type, MessageType.METHOD_RETURN)
        with self.assertRaises(asyncio.TimeoutError):
            await ui.next(timeout=0.3)
        await ui.close()

    async def test_unknown_device_service_authorization_asks(self):
        ui = Client(self.sock); await ui.connect()
        p = asyncio.ensure_future(self.call("AuthorizeService", "os", [DEV, "0000110b-0000-1000-8000-00805f9b34fb"]))
        ev = await ui.next(); self.assertEqual((ev["kind"], ev["uuid"][:8]), ("service", "0000110b"))
        ui.reply(ev["id"], True)
        self.assertEqual((await p).message_type, MessageType.METHOD_RETURN)
        await ui.close()

    # ---- commands: pair / connect with steps and real errors ----
    async def test_pair_reports_linking_then_done(self):
        ui = Client(self.sock); await ui.connect()
        ui.command("pair")
        steps = [e["step"] for e in await ui.statuses()]
        self.assertEqual(steps, ["linking", "done"])
        self.assertIn("Pair", self.dev.calls)
        await ui.close()

    async def test_pair_failure_carries_bluez_error_and_friendly_reason(self):
        self.dev.fail = ("org.bluez.Error.AuthenticationTimeout", "Authentication Timeout")
        ui = Client(self.sock); await ui.connect()
        ui.command("pair")
        last = (await ui.statuses())[-1]
        self.assertEqual((last["step"], last["error"]), ("failed", "org.bluez.Error.AuthenticationTimeout"))
        self.assertIn("Bluetooth settings", last["reason"])
        await ui.close()

    async def test_generic_failed_error_is_translated_from_its_message(self):
        self.dev.fail = ("org.bluez.Error.Failed", "br-connection-page-timeout")
        ui = Client(self.sock); await ui.connect()
        ui.command("connect")
        last = (await ui.statuses())[-1]
        self.assertIn("page timeout", last["reason"])
        await ui.close()

    async def test_connect_reports_link_and_services_steps(self):
        ui = Client(self.sock); await ui.connect()
        ui.command("connect")
        steps = [e["step"] for e in await ui.statuses()]
        self.assertEqual(steps[0], "linking")
        self.assertEqual(steps[-1], "done")
        self.assertIn("linked", steps)
        self.assertIn("resolved", steps)
        await ui.close()

    async def test_cancel_aborts_a_pair_in_flight(self):
        self.dev.hang = True
        ui = Client(self.sock); await ui.connect()
        ui.command("pair")
        self.assertEqual((await ui.next())["step"], "linking")
        ui.command("cancel")
        last = (await ui.statuses())[-1]
        self.assertEqual((last["step"], last["reason"]), ("failed", "cancelled"))
        self.assertIn("CancelPairing", self.dev.calls)
        await ui.close()

    async def test_unknown_device_fails_cleanly(self):
        ui = Client(self.sock); await ui.connect()
        ui.command("pair", "00:00:00:00:00:00")
        last = (await ui.statuses())[-1]
        self.assertEqual(last["error"], "org.bluez.Error.DoesNotExist")
        await ui.close()

    def test_friendly_error_fallbacks(self):
        self.assertEqual(agent_mod.friendly_error("org.bluez.Error.Whatever", "some text"), "some text")
        self.assertIn("rejected", agent_mod.friendly_error("org.bluez.Error.AuthenticationRejected"))

    # ---- no UI: old agent's behaviour ----
    async def test_without_ui_confirm_and_authorize_are_accepted(self):
        for member, sig, body in (("RequestConfirmation", "ou", [DEV, 7]), ("RequestAuthorization", "o", [DEV]),
                                  ("AuthorizeService", "os", [DEV, "x"])):
            self.assertEqual((await self.call(member, sig, body)).message_type, MessageType.METHOD_RETURN, member)

    async def test_without_ui_typed_input_is_rejected(self):
        for member in ("RequestPinCode", "RequestPasskey"):
            r = await self.call(member, "o", [DEV])
            self.assertEqual(r.error_name, "org.bluez.Error.Rejected", member)


if __name__ == "__main__":
    unittest.main()

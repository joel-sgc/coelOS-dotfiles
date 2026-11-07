#!/usr/bin/env python3
"""A tiny fake wpa_supplicant on the *session* bus, for testing miracast-linkd
without root or hardware. Implements just what the daemon uses.

  python3 mock_wpa.py            # runs until killed; after Find() it announces two TVs
"""
import asyncio

from dbus_fast import Variant
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, method, signal, dbus_property, PropertyAccess
from dbus_fast import BusType

IFACE = "/fi/w1/wpa_supplicant1/Interfaces/7"
FIRE = {
    "DeviceName": Variant("s", "Joel's Fire TV"),
    "ModelName": Variant("s", "UB134_STATION"),
    "PrimaryDeviceType": Variant("ay", bytes([0, 10, 0, 80, 242, 4, 0, 5])),
    "level": Variant("i", -60),
    "groupcapability": Variant("y", 0),
    "IEs": Variant("ay", bytes([0, 0, 6, 0, 17, 28, 68, 0, 50])),
    "DeviceAddress": Variant("ay", bytes([106, 154, 135, 60, 78, 180])),
}
BEDROOM = {
    "DeviceName": Variant("s", "bedroom tv"),
    "PrimaryDeviceType": Variant("ay", bytes([0, 7, 0, 80, 242, 4, 0, 1])),
    "level": Variant("i", -70),
    "groupcapability": Variant("y", 0),
    "IEs": Variant("ay", bytes([0, 0, 6, 1, 17, 28, 68, 0, 54])),
    "DeviceAddress": Variant("ay", bytes([0x3a, 0x8c, 0xef, 0x1d, 0x2a, 0x15])),
}


class Root(ServiceInterface):
    def __init__(self):
        super().__init__("fi.w1.wpa_supplicant1")
        self.wfd = b""

    @dbus_property(access=PropertyAccess.READ)
    def Interfaces(self) -> "ao":
        return [IFACE]

    @dbus_property()
    def WFDIEs(self) -> "ay":
        return self.wfd

    @WFDIEs.setter
    def WFDIEs(self, v: "ay"):
        self.wfd = bytes(v)


class Iface(ServiceInterface):
    def __init__(self):
        super().__init__("fi.w1.wpa_supplicant1.Interface")

    @dbus_property(access=PropertyAccess.READ)
    def Ifname(self) -> "s":
        return "wlp1s0"


class P2P(ServiceInterface):
    def __init__(self):
        super().__init__("fi.w1.wpa_supplicant1.Interface.P2PDevice")
        self.found = []
        self.cfg = {"DeviceName": "mock"}

    @dbus_property(access=PropertyAccess.READ)
    def Peers(self) -> "ao":
        return []

    @dbus_property()
    def P2PDeviceConfig(self) -> "a{sv}":
        return {k: Variant("s", v) for k, v in self.cfg.items()}

    @P2PDeviceConfig.setter
    def P2PDeviceConfig(self, v: "a{sv}"):
        self.cfg = {k: x.value for k, x in v.items()}

    @method()
    def Find(self, args: "a{sv}"):
        asyncio.get_event_loop().call_later(0.3, self.announce)

    @method()
    def StopFind(self):
        pass

    @method()
    def Flush(self):
        pass

    @signal()
    def DeviceFoundProperties(self, path: "o", props: "a{sv}") -> "oa{sv}":
        return [path, props]

    @signal()
    def DeviceLost(self, path: "o") -> "o":
        return path

    @signal()
    def GroupFormationFailure(self, reason: "s") -> "s":
        return reason

    @method()
    def Connect(self, args: "a{sv}") -> "s":
        """Always fails formation, like a TV that drops the last step."""
        self.connects = getattr(self, "connects", 0) + 1
        asyncio.get_event_loop().call_later(0.3, self.GroupFormationFailure, "FORMATION_FAILED")
        return ""

    def announce(self):
        self.DeviceFoundProperties(IFACE + "/Peers/6a9a873c4eb4", FIRE)
        self.DeviceFoundProperties(IFACE + "/Peers/3a8cef1d2a15", BEDROOM)


async def main():
    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    bus.export("/fi/w1/wpa_supplicant1", Root())
    p2p = P2P()
    bus.export(IFACE, Iface())
    bus.export(IFACE, p2p)
    await bus.request_name("fi.w1.wpa_supplicant1")
    print("mock wpa ready", flush=True)
    await asyncio.get_event_loop().create_future()


if __name__ == "__main__":
    asyncio.run(main())

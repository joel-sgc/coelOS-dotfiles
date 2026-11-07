"""Offline tests for the pure helpers (no D-Bus, no root).

Run:  python3 -m unittest test_miracast_linkd   (from this directory)

The fixture is the Fire TV's DeviceFoundProperties as captured from
wpa_supplicant 2.12 on this machine.
"""
import time
import unittest

import miracast_linkd as m

FIRE_TV = {
    "DeviceName": "Joel's Fire TV",
    "Manufacturer": " ",
    "ModelName": "UB134_STATION",
    "PrimaryDeviceType": bytes([0, 10, 0, 80, 242, 4, 0, 5]),
    "config_method": 392,
    "level": -60,
    "devicecapability": 37,
    "groupcapability": 0,
    "IEs": bytes([0, 0, 6, 0, 17, 28, 68, 0, 50]),
    "DeviceAddress": bytes([106, 154, 135, 60, 78, 180]),
}
# the other TV that showed up in the log: 'bedroom tv', wfd_dev_info=0x01111c440036
BEDROOM = {
    "DeviceName": "bedroom tv",
    "PrimaryDeviceType": bytes([0, 7, 0, 80, 242, 4, 0, 1]),
    "level": -70,
    "groupcapability": 0,
    "IEs": bytes([0, 0, 6, 1, 17, 28, 68, 0, 54]),
    "DeviceAddress": bytes([0x3a, 0x8c, 0xef, 0x1d, 0x2a, 0x15]),
}


class Helpers(unittest.TestCase):
    def test_mac(self):
        self.assertEqual(m.mac_str(bytes([106, 154, 135, 60, 78, 180])), "6a:9a:87:3c:4e:b4")
        self.assertEqual(m.mac_from_peer_path("/x/Interfaces/14/Peers/6a9a873c4eb4"), "6a:9a:87:3c:4e:b4")
        self.assertIsNone(m.mac_from_peer_path("/x/Peers/short"))

    def test_device_type(self):
        self.assertEqual(m.primary_device_type(FIRE_TV["PrimaryDeviceType"]), "10-0050F204-5")
        self.assertEqual(m.primary_device_type(b""), "")

    def test_wfd_sink(self):
        w = m.parse_wfd_ies(FIRE_TV["IEs"])
        self.assertTrue(w["is_sink"])
        self.assertEqual(w["role"], "sink")
        self.assertTrue(w["session_available"])
        self.assertEqual(w["port"], 7236)
        self.assertEqual(w["max_throughput"], 50)

    def test_wfd_content_protection_bit(self):
        w = m.parse_wfd_ies(BEDROOM["IEs"])
        self.assertTrue(w["is_sink"])
        self.assertTrue(w["content_protection"])
        self.assertEqual(w["max_throughput"], 54)

    def test_wfd_garbage(self):
        self.assertEqual(m.parse_wfd_ies(b""), {})
        self.assertEqual(m.parse_wfd_ies(bytes([0, 0])), {})
        self.assertEqual(m.parse_wfd_ies(bytes([0, 0, 6, 0])), {})  # truncated

    def test_build_wfd_ies_is_a_source(self):
        w = m.parse_wfd_ies(m.build_wfd_ies(7236, 50))
        self.assertEqual(w["role"], "source")
        self.assertFalse(w["is_sink"])
        self.assertTrue(w["session_available"])
        self.assertEqual(w["port"], 7236)

    def test_peer_record(self):
        r = m.peer_record(FIRE_TV, now=1000.0)
        self.assertEqual(r["address"], "6a:9a:87:3c:4e:b4")
        self.assertEqual(r["name"], "Joel's Fire TV")
        self.assertEqual(r["manufacturer"], "")
        self.assertTrue(r["is_sink"])
        self.assertEqual(r["rssi"], -60)


class LeaseTests(unittest.TestCase):
    def test_lease(self):
        r = m.parse_lease('{"ip":"192.168.49.54","mask":"24","router":"192.168.49.1","serverid":"192.168.49.1"}')
        self.assertEqual(r, {"ip": "192.168.49.54", "mask": "24", "router": "192.168.49.1"})

    def test_lease_router_falls_back_to_server(self):
        r = m.parse_lease('{"ip":"10.0.0.2","mask":"24","router":"","serverid":"10.0.0.1"}')
        self.assertEqual(r["router"], "10.0.0.1")

    def test_lease_garbage(self):
        self.assertIsNone(m.parse_lease("not json"))
        self.assertIsNone(m.parse_lease('{"mask":"24"}'))
        self.assertIsNone(m.parse_lease("[]"))


class StateTests(unittest.TestCase):
    def test_expiry_and_ordering(self):
        s = m.State(peer_ttl=60)
        now = time.time()
        a = m.peer_record(FIRE_TV, now=now)
        b = m.peer_record(BEDROOM, now=now - 100)
        s.peers[a["address"]] = a
        s.peers[b["address"]] = b
        self.assertTrue(s.expire(now))
        self.assertEqual(list(s.peers), [a["address"]])
        j = s.to_json(now)
        self.assertEqual(j["peers"][0]["name"], "Joel's Fire TV")
        self.assertEqual(j["version"], 1)

    def test_sinks_sort_first(self):
        s = m.State(peer_ttl=60)
        now = time.time()
        phone = m.peer_record({"DeviceName": "Phone", "IEs": b"", "DeviceAddress": bytes(range(1, 7))}, now=now)
        tv = m.peer_record(FIRE_TV, now=now)
        s.peers[phone["address"]] = phone
        s.peers[tv["address"]] = tv
        self.assertEqual([p["name"] for p in s.to_json(now)["peers"]], ["Joel's Fire TV", "Phone"])


if __name__ == "__main__":
    unittest.main()

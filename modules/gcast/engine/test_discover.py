import unittest

import discover

BROWSE = r'''+;wlp1s0;IPv4;Chromecast-abc;_googlecast._tcp;local
=;wlp1s0;IPv6;Chromecast-abc;_googlecast._tcp;local;abc.local;fe80::1;8009;"id=abc123" "fn=Living Room" "md=Chromecast"
=;wlp1s0;IPv4;Chromecast-abc;_googlecast._tcp;local;abc.local;192.168.0.50;8009;"id=abc123" "cd=XYZ" "ve=05" "md=Chromecast" "fn=Living Room" "ca=201221" "st=0"
=;wlp1s0;IPv4;Google-Home-Mini-77;_googlecast._tcp;local;mini.local;192.168.0.61;8009;"id=77ff" "md=Google Home Mini" "fn=Kitchen speaker \039s"
=;wlp1s0;IPv4;Joel's Fire TV;_airplay._tcp;local;fire.local;192.168.0.70;7000;"model=x"
'''


class ParseTests(unittest.TestCase):
    def test_devices_are_deduplicated_and_ipv4_first(self):
        devs = discover.parse_browse(BROWSE)
        self.assertEqual(devs[0]["name"], "Kitchen speaker 's")
        living = [d for d in devs if d["name"] == "Living Room"][0]
        self.assertEqual(living["addresses"], ["192.168.0.50", "fe80::1"])
        self.assertEqual((living["id"], living["model"], living["port"]), ("abc123", "Chromecast", 8009))
        self.assertEqual(len(devs), 2)                                  # the AirPlay service is not a Cast device

    def test_txt_escapes(self):
        self.assertEqual(discover.parse_txt('"fn=a\\032b" "x=1"'), {"fn": "a b", "x": "1"})

    def test_ignores_noise(self):
        self.assertEqual(discover.parse_browse("garbage\n+;a;b\n"), [])


class FindTests(unittest.TestCase):
    def setUp(self):
        self.devs = discover.parse_browse(BROWSE)

    def test_by_name_part_model_id_and_address(self):
        self.assertEqual(discover.find(self.devs, "living")["id"], "abc123")
        self.assertEqual(discover.find(self.devs, "home mini")["id"], "77ff")
        self.assertEqual(discover.find(self.devs, "abc123")["name"], "Living Room")
        self.assertEqual(discover.find(self.devs, "192.168.0.61")["id"], "77ff")

    def test_no_match_and_ambiguous(self):
        with self.assertRaises(ValueError):
            discover.find(self.devs, "bedroom")
        with self.assertRaises(ValueError):
            discover.find(self.devs, "e")                               # matches both


class BrowseTests(unittest.IsolatedAsyncioTestCase):
    """browse() against a stand-in avahi-browse: the live pass (-rp) streams and is cut off, the cached pass (-rpt) ends."""

    def fake(self, live, cached):
        import os
        import stat
        import tempfile
        d = tempfile.mkdtemp()
        path = os.path.join(d, "avahi-browse")
        with open(path, "w") as f:
            f.write("#!/bin/sh\ncase \"$1\" in\n  -rp) printf '%s' '" + live.replace("'", "'\\''") + "'; sleep 30 ;;\n"
                    "  -rpt) printf '%s' '" + cached.replace("'", "'\\''") + "' ;;\nesac\n")
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        return path

    async def test_merges_live_and_cached_results(self):
        line = lambda n, a, i: "=;wlp1s0;IPv4;%s;_googlecast._tcp;local;h.local;%s;8009;\"id=%s\" \"fn=%s\"\n" % (n, a, i, n)  # noqa: E731
        exe = self.fake(line("One", "192.168.0.5", "1"), line("Two", "192.168.0.6", "2"))
        devs = await discover.browse(1.0, avahi_browse=exe)
        self.assertEqual([d["name"] for d in devs], ["One", "Two"])

    async def test_missing_avahi_is_a_clear_error(self):
        with self.assertRaises(RuntimeError):
            await discover.browse(0.5, avahi_browse="/nonexistent/avahi-browse")


if __name__ == "__main__":
    unittest.main()

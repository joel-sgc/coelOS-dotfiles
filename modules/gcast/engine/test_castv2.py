import asyncio
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests"))
import castv2  # noqa: E402
import mock_cast  # noqa: E402


class CodecTests(unittest.TestCase):
    def test_roundtrip(self):
        m = castv2.encode_message("sender-0", "receiver-0", castv2.NS_RECEIVER, '{"type":"GET_STATUS","requestId":1}')
        d = castv2.decode_message(m)
        self.assertEqual((d["source"], d["destination"], d["namespace"]),
                         ("sender-0", "receiver-0", castv2.NS_RECEIVER))
        self.assertEqual(d["payload"], '{"type":"GET_STATUS","requestId":1}')

    def test_field_layout_matches_the_cast_channel_proto(self):
        m = castv2.encode_message("a", "b", "n", "p")
        # 08 00 (protocol_version=0) 12 01 'a' 1a 01 'b' 22 01 'n' 28 00 (payload_type=STRING) 32 01 'p'
        self.assertEqual(m.hex(), "0800" "120161" "1a0162" "22016e" "2800" "320170")

    def test_binary_payload(self):
        d = castv2.decode_message(castv2.encode_message("a", "b", "n", b"\x00\x01", binary=True))
        self.assertEqual(d["payload_binary"], b"\x00\x01")
        self.assertIsNone(d["payload"])

    def test_long_payload_uses_a_multibyte_varint(self):
        payload = "x" * 300
        self.assertEqual(castv2.decode_message(castv2.encode_message("a", "b", "n", payload))["payload"], payload)

    def test_frame_length_prefix(self):
        f = castv2.frame(b"abc")
        self.assertEqual(f, b"\x00\x00\x00\x03abc")

    def test_truncated_input_is_an_error(self):
        with self.assertRaises(castv2.CastError):
            castv2.decode_message(b"\x12\x05ab")


@unittest.skipUnless(os.path.exists("/usr/bin/openssl") or os.system("which openssl >/dev/null 2>&1") == 0, "needs openssl")
class ClientAgainstMockTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.dir = tempfile.mkdtemp()
        cert, key = mock_cast.make_cert(self.dir)
        self.mock = mock_cast.MockCast()
        self.server = await mock_cast.serve(self.mock, cert, key, 0)
        self.port = self.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()

    async def test_launch_default_media_receiver(self):
        async with castv2.CastClient("127.0.0.1", self.port, heartbeat=0.2) as cast:
            self.assertEqual(await cast.get_status(), {"volume": {"level": 1.0, "muted": False}})
            app = await cast.launch(castv2.DEFAULT_MEDIA_RECEIVER)
            self.assertEqual((app["appId"], app["transportId"]), ("CC1AD845", "web-1"))
            await asyncio.sleep(0.5)
        kinds = [(ns.split(".")[-1], b.get("type")) for ns, _, b in self.mock.log]
        self.assertIn(("connection", "CONNECT"), kinds)
        self.assertIn(("receiver", "LAUNCH"), kinds)
        self.assertGreaterEqual(self.mock.pongs, 1)                      # heartbeat was sent and answered
        connects = [d for ns, d, b in self.mock.log if ns == castv2.NS_CONNECTION and b["type"] == "CONNECT"]
        self.assertEqual(connects, ["receiver-0", "web-1"])               # platform first, then the launched app

    async def test_load_failure_is_reported(self):
        self.mock.fail_load = True
        async with castv2.CastClient("127.0.0.1", self.port) as cast:
            app = await cast.launch()
            with self.assertRaises(castv2.CastError) as ctx:
                await cast.load(app, "http://127.0.0.1:1/x/live.m3u8", "application/x-mpegURL")
            self.assertIn("LOAD_FAILED", str(ctx.exception))

    async def test_connect_failure_message(self):
        with self.assertRaises(castv2.CastError):
            await castv2.CastClient("127.0.0.1", 1).connect(timeout=2)


if __name__ == "__main__":
    unittest.main()

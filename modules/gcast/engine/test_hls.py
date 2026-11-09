import asyncio
import os
import tempfile
import unittest
import urllib.error
import urllib.request

import hls


def fetch(url, method="GET"):
    req = urllib.request.Request(url, method=method, headers={"Origin": "https://example"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), b""


class ServerTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.dir = tempfile.mkdtemp()
        with open(os.path.join(self.dir, "live.m3u8"), "w") as f:
            f.write("#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:1.0,\nseg0.ts\n#EXTINF:1.0,\nseg1.ts\n")
        for n in ("seg0.ts", "seg1.ts"):
            with open(os.path.join(self.dir, n), "wb") as f:
                f.write(b"\x47" + b"\0" * 187)
        with open(os.path.join(self.dir, "secret.txt"), "w") as f:
            f.write("no")
        self.server = await hls.HlsServer(self.dir, allowed_ip="127.0.0.1").start()
        self.loop = asyncio.get_running_loop()

    async def asyncTearDown(self):
        await self.server.stop()

    async def get(self, url, method="GET"):
        return await self.loop.run_in_executor(None, fetch, url, method)

    async def test_playlist_and_segment_with_cors_and_types(self):
        status, h, body = await self.get(self.server.url("127.0.0.1"))
        self.assertEqual(status, 200)
        self.assertTrue(body.startswith(b"#EXTM3U"))
        self.assertEqual(h["Access-Control-Allow-Origin"], "*")
        self.assertEqual(h["Content-Type"], "application/vnd.apple.mpegurl")
        self.assertIn("no-cache", h["Cache-Control"])
        status, h, body = await self.get(self.server.url("127.0.0.1", "seg0.ts"))
        self.assertEqual((status, h["Content-Type"], body[0]), (200, "video/mp2t", 0x47))
        self.assertEqual(h["Access-Control-Allow-Origin"], "*")

    async def test_wrong_token_traversal_and_other_files_are_refused(self):
        base = "http://127.0.0.1:%d" % self.server.port
        for path in ("/wrong/live.m3u8", "/%s/secret.txt" % self.server.token, "/%s/../etc/passwd" % self.server.token,
                     "/%s/%%2e%%2e%%2fetc%%2fpasswd" % self.server.token, "/"):
            self.assertEqual((await self.get(base + path))[0], 404, path)

    async def test_only_the_device_may_fetch(self):
        self.server.allowed_ip = "10.9.9.9"
        status, h, _ = await self.get(self.server.url("127.0.0.1"))
        self.assertEqual(status, 403)
        self.assertEqual(h.get("Access-Control-Allow-Origin"), "*")

    async def test_options_and_head(self):
        self.assertEqual((await self.get(self.server.url("127.0.0.1"), "OPTIONS"))[0], 204)
        status, h, body = await self.get(self.server.url("127.0.0.1"), "HEAD")
        self.assertEqual((status, body), (200, b""))
        self.assertGreater(int(h["Content-Length"]), 0)

    def test_wait_ready(self):
        self.assertTrue(hls.wait_ready(self.dir, 2))
        self.assertFalse(hls.wait_ready(self.dir, 3))
        self.assertFalse(hls.wait_ready("/nonexistent"))


if __name__ == "__main__":
    unittest.main()

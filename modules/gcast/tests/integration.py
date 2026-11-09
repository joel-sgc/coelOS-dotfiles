"""gcast_engine end to end against the mock Cast device (needs gst-launch-1.0 with x264/hlssink2/fdkaac and openssl).

    PATH=<gstreamer>/bin GST_PLUGIN_SYSTEM_PATH_1_0=... python3 -m unittest tests/integration.py
"""
import asyncio
import json
import os
import shutil
import signal
import sys
import tempfile
import unittest

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
sys.path.insert(0, os.path.join(here, "..", "engine"))
import castv2  # noqa: E402
import mock_cast  # noqa: E402

ENGINE = os.path.join(here, "..", "engine", "gcast_engine.py")


@unittest.skipUnless(shutil.which("gst-launch-1.0") and shutil.which("openssl"), "needs gst-launch-1.0 and openssl")
class EngineTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.dir = tempfile.mkdtemp()
        cert, key = mock_cast.make_cert(self.dir)
        self.mock = mock_cast.MockCast()
        self.server = await mock_cast.serve(self.mock, cert, key, 0)
        self.port = self.server.sockets[0].getsockname()[1]
        self.status_file = os.path.join(self.dir, "status.json")

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()
        shutil.rmtree(self.dir, ignore_errors=True)

    def status(self):
        try:
            with open(self.status_file) as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    async def start_engine(self, *extra):
        env = dict(os.environ, XDG_RUNTIME_DIR=self.dir)
        return await asyncio.create_subprocess_exec(
            sys.executable, ENGINE, "--host", "127.0.0.1", "--port", str(self.port), "--name", "Mock", "--source", "test",
            "--http-port", "0", "--audio-source", "tone", "--status-file", self.status_file, *extra,
            stderr=asyncio.subprocess.PIPE, env=env)

    async def wait_state(self, proc, states, timeout=40):
        end = asyncio.get_running_loop().time() + timeout
        while asyncio.get_running_loop().time() < end:
            if self.status().get("state") in states:
                return self.status()
            if proc.returncode is not None:
                break
            await asyncio.sleep(0.25)
        err = (await proc.stderr.read()).decode(errors="replace")[-800:] if proc.returncode is not None else ""
        self.fail("engine did not reach %s (status %s) %s" % (states, self.status(), err))

    async def test_casts_an_hls_stream_and_stops_cleanly(self):
        proc = await self.start_engine()
        st = await self.wait_state(proc, {"casting", "error"})
        self.assertEqual(st["state"], "casting", st)
        # what the device was told
        kinds = [(b.get("type"), b.get("appId")) for ns, _, b in self.mock.log if b.get("type") == "LAUNCH"]
        self.assertEqual(kinds, [("LAUNCH", "CC1AD845")])
        load = [b for ns, _, b in self.mock.log if b.get("type") == "LOAD"][0]
        self.assertEqual(load["media"]["contentType"], "application/x-mpegURL")
        self.assertEqual(load["media"]["streamType"], "LIVE")
        self.assertTrue(load["autoplay"])
        self.assertRegex(load["media"]["contentId"], r"^http://127\.0\.0\.1:\d+/[\w-]+/live\.m3u8$")
        # what the device fetched: the playlist, then a real MPEG-TS segment, with CORS
        urls = [u for u, s, h in self.mock.fetched if s == 200]
        self.assertTrue(any(u.endswith("live.m3u8") for u in urls), urls)
        self.assertTrue(any(u.endswith(".ts") for u in urls), urls)
        # stop: the device is told to stop the app, the status says so, the HLS directory is removed
        proc.send_signal(signal.SIGTERM)
        await asyncio.wait_for(proc.wait(), 20)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(self.status()["state"], "ended")
        self.assertIn("STOP", [b.get("type") for ns, _, b in self.mock.log])
        self.assertFalse([d for d in os.listdir(self.dir) if d.startswith("gcast-")])

    async def test_a_refused_stream_is_reported(self):
        self.mock.fail_load = True
        proc = await self.start_engine()
        st = await self.wait_state(proc, {"error", "casting"})
        self.assertEqual(st["state"], "error")
        self.assertIn("LOAD_FAILED", st["error"])
        await asyncio.wait_for(proc.wait(), 20)
        self.assertEqual(proc.returncode, 1)

    async def test_unreachable_device_is_reported(self):
        proc = await asyncio.create_subprocess_exec(
            sys.executable, ENGINE, "--host", "127.0.0.1", "--port", "1", "--source", "test", "--http-port", "0",
            "--status-file", self.status_file, stderr=asyncio.subprocess.PIPE, env=dict(os.environ, XDG_RUNTIME_DIR=self.dir))
        await asyncio.wait_for(proc.wait(), 60)
        self.assertEqual(self.status()["state"], "error")
        self.assertIn("cannot connect", self.status()["error"])


if __name__ == "__main__":
    unittest.main()

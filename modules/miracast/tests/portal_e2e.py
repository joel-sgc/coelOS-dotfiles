"""portal_capture against the mock portal (run inside run-with-bus; needs dbus-fast)."""
import asyncio
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "castlib"))
import portal_capture  # noqa: E402

here = os.path.dirname(os.path.abspath(__file__))


async def run(cancel):
    mock = subprocess.Popen([sys.executable, os.path.join(here, "mock_portal.py")] + (["--cancel"] if cancel else []),
                            stdout=subprocess.PIPE, text=True)
    mock.stdout.readline()
    logs = []
    loop = asyncio.get_running_loop()
    try:
        if cancel:
            try:
                await portal_capture.open_screencast(loop, logs.append, timeout=10)
                print("FAIL: cancel was not reported")
                return 1
            except portal_capture.CaptureError as e:
                assert "cancelled" in str(e), e
                print("cancel ->", e)
                return 0
        cap = await portal_capture.open_screencast(loop, logs.append, timeout=10)
        print("node", cap.node, "fd", cap.fd, "logs", logs)
        assert cap.node == 4242
        assert os.fstat(cap.fd)            # a real, open descriptor came through
        await cap.close()
        time.sleep(0.3)
        return 0
    finally:
        mock.terminate()


rc = asyncio.run(run(False)) or asyncio.run(run(True))
print("OK" if rc == 0 else "FAILED")
sys.exit(rc)

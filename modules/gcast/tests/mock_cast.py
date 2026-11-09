#!/usr/bin/env python3
"""A fake Google Cast device for testing the sender without hardware.

Speaks CASTV2 over TLS like a Chromecast with the Default Media Receiver:

    CONNECT -> (heartbeat PING/PONG) -> GET_STATUS -> LAUNCH CC1AD845 -> RECEIVER_STATUS{transportId}
    CONNECT(transportId) -> LOAD{contentId,...} -> it FETCHES the playlist and the first segment over HTTP like the
    real receiver does (checking the CORS header, content types and that the playlist is a live HLS one) ->
    MEDIA_STATUS PLAYING  (or LOAD_FAILED with the reason)

Everything it receives is recorded in `.log` for assertions. `--fail-load` makes it answer LOAD_FAILED.

    python3 mock_cast.py --cert c.pem --key k.pem --port 18009
"""
import argparse
import asyncio
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "engine"))
import castv2  # noqa: E402


class MockCast:
    def __init__(self, fail_load=False, require_cors=True, deaf_to_heartbeat=False):
        self.fail_load = fail_load
        self.require_cors = require_cors
        self.log = []                      # (namespace, dest, json body) of everything received
        self.fetched = []                  # (url, status, headers) of the HTTP fetches
        self.app = None
        self.pongs = 0

    def media_status(self, state="PLAYING", rid=0):
        return {"type": "MEDIA_STATUS", "requestId": rid, "status": [{
            "mediaSessionId": 1, "playerState": state, "currentTime": 0.0,
            "media": {"contentId": self.app and self.app.get("loaded")}}]}

    def _fetch(self, url):
        req = urllib.request.Request(url, headers={"Origin": "https://www.gstatic.com",
                                                   "User-Agent": "CrKey/mock"})
        try:
            with urllib.request.urlopen(req, timeout=8) as r:
                body = r.read()
                self.fetched.append((url, r.status, dict(r.headers)))
                return r.status, dict(r.headers), body
        except urllib.error.HTTPError as e:
            self.fetched.append((url, e.code, dict(e.headers)))
            return e.code, dict(e.headers), b""
        except Exception as e:  # noqa: BLE001
            self.fetched.append((url, 0, {"error": str(e)}))
            return 0, {}, b""

    def check_stream(self, url):
        """What a receiver needs from an HLS live URL. Returns an error string or None."""
        status, headers, body = self._fetch(url)
        if status != 200:
            return "playlist fetch failed (%s)" % status
        h = {k.lower(): v for k, v in headers.items()}
        if self.require_cors and h.get("access-control-allow-origin") not in ("*", "https://www.gstatic.com"):
            return "playlist has no CORS header"
        text = body.decode(errors="replace")
        if not text.startswith("#EXTM3U"):
            return "not a playlist"
        if "#EXT-X-ENDLIST" in text:
            return "playlist is not live"
        segs = [l for l in text.splitlines() if l and not l.startswith("#")]
        if not segs:
            return "playlist has no segments"
        seg_url = urllib.request.urljoin(url, segs[0])
        status, headers, body = self._fetch(seg_url)
        if status != 200 or len(body) < 188 or body[0] != 0x47:
            return "first segment is not MPEG-TS (%s, %d bytes)" % (status, len(body))
        if self.require_cors and {k.lower(): v for k, v in headers.items()}.get("access-control-allow-origin") is None:
            return "segment has no CORS header"
        return None

    async def handle(self, reader, writer):
        def send(ns, body, dest, src=castv2.PLATFORM_ID):
            writer.write(castv2.frame(castv2.encode_message(src, dest, ns, json.dumps(body))))

        try:
            while True:
                msg = castv2.decode_message(await castv2.read_frame(reader))
                body = json.loads(msg["payload"] or "{}")
                ns, kind, src, dest = msg["namespace"], body.get("type"), msg["source"], msg["destination"]
                self.log.append((ns, dest, body))
                if ns == castv2.NS_HEARTBEAT and kind == "PING":
                    self.pongs += 1
                    send(ns, {"type": "PONG"}, src, dest)
                elif ns == castv2.NS_RECEIVER and kind == "GET_STATUS":
                    send(ns, {"type": "RECEIVER_STATUS", "requestId": body["requestId"], "status": self.status()}, src)
                elif ns == castv2.NS_RECEIVER and kind == "LAUNCH":
                    self.app = {"appId": body["appId"], "displayName": "Default Media Receiver",
                                "sessionId": "sess-1", "transportId": "web-1", "isIdleScreen": False,
                                "namespaces": [{"name": castv2.NS_MEDIA}]}
                    send(ns, {"type": "RECEIVER_STATUS", "requestId": body["requestId"], "status": self.status()}, src)
                elif ns == castv2.NS_RECEIVER and kind == "STOP":
                    self.app = None
                    send(ns, {"type": "RECEIVER_STATUS", "requestId": body["requestId"], "status": self.status()}, src)
                elif ns == castv2.NS_MEDIA and kind == "LOAD":
                    url = body["media"]["contentId"]
                    problem = "forced failure" if self.fail_load else await asyncio.get_running_loop().run_in_executor(
                        None, self.check_stream, url)
                    if problem:
                        send(ns, {"type": "LOAD_FAILED", "requestId": body["requestId"], "reason": problem}, src, "web-1")
                    else:
                        self.app["loaded"] = url
                        send(ns, self.media_status("PLAYING", body["requestId"]), src, "web-1")
                elif ns == castv2.NS_CONNECTION and kind == "CLOSE":
                    pass
                await writer.drain()
        except (asyncio.IncompleteReadError, ConnectionError, ssl.SSLError):
            pass
        finally:
            writer.close()

    def status(self):
        s = {"volume": {"level": 1.0, "muted": False}}
        if self.app:
            s["applications"] = [self.app]
        return s


async def serve(mock, cert, key, port, host="127.0.0.1"):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    return await asyncio.start_server(mock.handle, host, port, ssl=ctx)


def make_cert(directory):
    """Self-signed certificate, like a Cast device's."""
    import subprocess
    cert, key = os.path.join(directory, "cert.pem"), os.path.join(directory, "key.pem")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                    "-days", "1", "-subj", "/CN=mock-chromecast"], check=True, capture_output=True)
    return cert, key


async def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=18009)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--cert")
    p.add_argument("--key")
    p.add_argument("--fail-load", action="store_true")
    a = p.parse_args()
    cert, key = a.cert, a.key
    if not cert:
        import tempfile
        cert, key = make_cert(tempfile.mkdtemp())
    mock = MockCast(fail_load=a.fail_load)
    server = await serve(mock, cert, key, a.port, a.host)
    print("mock cast ready on %s:%d" % (a.host, a.port), flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())

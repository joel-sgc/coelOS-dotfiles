"""Serve a live HLS stream of the screen to one Cast device.

  GStreamer `hlssink2` writes `live.m3u8` plus short MPEG-TS segments into a private directory; `HlsServer` serves that
  directory over plain HTTP. Cast receivers fetch the media themselves, so:

  * the server must be reachable from the device (LAN address, firewall port open),
  * every response carries `Access-Control-Allow-Origin: *` (the receiver is a web page: no CORS header, no playback),
  * the URL contains a random token and only the device's IP may fetch: the screen is not published to the LAN.
"""

import asyncio
import os
import secrets
import socket
import urllib.parse

MIME = {".m3u8": "application/vnd.apple.mpegurl", ".ts": "video/mp2t"}


def local_ip_for(host):
    """The address of this machine that the device at `host` can reach (no packet is sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((host, 9))
        return s.getsockname()[0]
    finally:
        s.close()


class HlsServer:
    def __init__(self, directory, allowed_ip=None, port=0, bind="0.0.0.0", token=None, log=None):
        self.directory = os.path.realpath(directory)
        self.allowed_ip = allowed_ip
        self.port = port
        self.bind = bind
        self.token = token or secrets.token_urlsafe(12)
        self.log = log or (lambda m: None)
        self.server = None
        self.requests = []                       # (peer ip, path, status) for tests / status

    def url(self, host, name="live.m3u8"):
        return "http://%s:%d/%s/%s" % (host, self.port, self.token, name)

    async def start(self):
        self.server = await asyncio.start_server(self._handle, self.bind, self.port)
        self.port = self.server.sockets[0].getsockname()[1]
        return self

    async def stop(self):
        if self.server:
            self.server.close()
            await self.server.wait_closed()

    async def _respond(self, writer, status, reason, headers=None, body=b"", head=False):
        lines = ["HTTP/1.1 %d %s" % (status, reason), "Access-Control-Allow-Origin: *",
                 "Access-Control-Allow-Methods: GET, HEAD, OPTIONS", "Access-Control-Allow-Headers: *",
                 "Content-Length: %d" % len(body), "Connection: close"]
        lines += ["%s: %s" % kv for kv in (headers or {}).items()]
        writer.write(("\r\n".join(lines) + "\r\n\r\n").encode() + (b"" if head else body))
        await writer.drain()

    async def _handle(self, reader, writer):
        peer = writer.get_extra_info("peername")[0]
        status = 0
        path = "?"
        try:
            request = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 10)
            first = request.split(b"\r\n", 1)[0].decode(errors="replace").split()
            if len(first) < 2:
                status = 400
                return await self._respond(writer, 400, "Bad Request")
            method, target = first[0], urllib.parse.urlsplit(first[1]).path
            path = target
            if self.allowed_ip and peer != self.allowed_ip:
                status = 403
                return await self._respond(writer, 403, "Forbidden")
            if method == "OPTIONS":
                status = 204
                return await self._respond(writer, 204, "No Content")
            if method not in ("GET", "HEAD"):
                status = 405
                return await self._respond(writer, 405, "Method Not Allowed")
            parts = target.lstrip("/").split("/")
            if len(parts) != 2 or parts[0] != self.token:
                status = 404
                return await self._respond(writer, 404, "Not Found")
            name = urllib.parse.unquote(parts[1])
            full = os.path.realpath(os.path.join(self.directory, name))
            ext = os.path.splitext(name)[1]
            if os.path.dirname(full) != self.directory or ext not in MIME or not os.path.isfile(full):
                status = 404
                return await self._respond(writer, 404, "Not Found")
            with open(full, "rb") as f:
                body = f.read()
            headers = {"Content-Type": MIME[ext]}
            if ext == ".m3u8":
                headers["Cache-Control"] = "no-cache, no-store"
            status = 200
            await self._respond(writer, 200, "OK", headers, body, head=(method == "HEAD"))
        except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError, asyncio.LimitOverrunError):
            pass
        finally:
            self.requests.append((peer, path, status))
            try:
                writer.close()
            except Exception:
                pass


def wait_ready(directory, segments=2):
    """True once the playlist lists at least `segments` segments."""
    try:
        with open(os.path.join(directory, "live.m3u8")) as f:
            text = f.read()
    except OSError:
        return False
    return text.startswith("#EXTM3U") and sum(1 for l in text.splitlines() if l.endswith(".ts")) >= segments

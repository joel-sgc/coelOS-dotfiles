"""Google Cast (CASTV2) sender client, stdlib only.

Wire format: TLS to port 8009 (the device's certificate is self-signed, so it is not verified); every message is a
32-bit big-endian length followed by a protobuf `CastMessage`. The protobuf is tiny, so it is encoded by hand here
(no protobuf dependency). Payloads are JSON strings in namespaces:

    urn:x-cast:com.google.cast.tp.connection   CONNECT / CLOSE         (virtual connections)
    urn:x-cast:com.google.cast.tp.heartbeat    PING / PONG             (every ~5 s or the device drops us)
    urn:x-cast:com.google.cast.receiver        GET_STATUS / LAUNCH / STOP -> RECEIVER_STATUS
    urn:x-cast:com.google.cast.media           LOAD -> MEDIA_STATUS      (to the launched app's transportId)

Typical use (play an HLS URL with the Default Media Receiver):

    async with CastClient("192.168.0.50") as cast:
        app = await cast.launch(DEFAULT_MEDIA_RECEIVER)
        await cast.load(app, "http://192.168.0.40:8765/x/live.m3u8", "application/x-mpegURL")
"""

import asyncio
import json
import ssl
import struct

DEFAULT_MEDIA_RECEIVER = "CC1AD845"

NS_CONNECTION = "urn:x-cast:com.google.cast.tp.connection"
NS_HEARTBEAT = "urn:x-cast:com.google.cast.tp.heartbeat"
NS_RECEIVER = "urn:x-cast:com.google.cast.receiver"
NS_MEDIA = "urn:x-cast:com.google.cast.media"

PLATFORM_ID = "receiver-0"
HEARTBEAT_SECONDS = 5


class CastError(Exception):
    pass


# --------------------------------------------------------------------------- protobuf (CastMessage)

def _varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _read_varint(buf, i):
    shift = result = 0
    while True:
        if i >= len(buf):
            raise CastError("truncated varint")
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, i
        shift += 7


def encode_message(source, destination, namespace, payload, binary=False):
    """CastMessage {protocol_version=CASTV2_1_0, source_id, destination_id, namespace, payload_type, payload}."""
    def field_len(num, data):
        return _varint((num << 3) | 2) + _varint(len(data)) + data

    out = bytearray()
    out += _varint((1 << 3) | 0) + _varint(0)                       # protocol_version = CASTV2_1_0
    out += field_len(2, source.encode())
    out += field_len(3, destination.encode())
    out += field_len(4, namespace.encode())
    out += _varint((5 << 3) | 0) + _varint(1 if binary else 0)       # payload_type STRING / BINARY
    if binary:
        out += field_len(7, payload)
    else:
        out += field_len(6, payload.encode())
    return bytes(out)


def decode_message(buf):
    """-> dict(source, destination, namespace, payload (str) | payload_binary)."""
    msg = {"source": "", "destination": "", "namespace": "", "payload": None, "payload_binary": None}
    i = 0
    while i < len(buf):
        tag, i = _read_varint(buf, i)
        num, wire = tag >> 3, tag & 7
        if wire == 0:
            _, i = _read_varint(buf, i)
        elif wire == 2:
            length, i = _read_varint(buf, i)
            data = bytes(buf[i:i + length])
            if len(data) != length:
                raise CastError("truncated field %d" % num)
            i += length
            if num == 2:
                msg["source"] = data.decode()
            elif num == 3:
                msg["destination"] = data.decode()
            elif num == 4:
                msg["namespace"] = data.decode()
            elif num == 6:
                msg["payload"] = data.decode()
            elif num == 7:
                msg["payload_binary"] = data
        else:
            raise CastError("unsupported wire type %d" % wire)
    return msg


def frame(message):
    return struct.pack(">I", len(message)) + message


async def read_frame(reader):
    header = await reader.readexactly(4)
    (length,) = struct.unpack(">I", header)
    if length > 16 * 1024 * 1024:
        raise CastError("absurd frame length %d" % length)
    return await reader.readexactly(length)


# --------------------------------------------------------------------------- client

def insecure_context():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


class CastClient:
    def __init__(self, host, port=8009, sender_id="sender-0", log=None, ssl_context=None, heartbeat=HEARTBEAT_SECONDS):
        self.host, self.port = host, port
        self.sender_id = sender_id
        self.log = log or (lambda m: None)
        self.ssl = ssl_context or insecure_context()
        self.heartbeat = heartbeat
        self.reader = self.writer = None
        self._request_id = 0
        self._waiters = {}                  # requestId -> Future
        self._tasks = []
        self.closed = asyncio.Event()
        self.receiver_status = {}           # latest RECEIVER_STATUS `status`
        self.media_status = {}              # latest MEDIA_STATUS entry
        self.on_media_status = None         # optional callback(status_dict)
        self._connected = set()             # destination ids with a virtual connection

    async def __aenter__(self):
        await self.connect()
        return self

    async def __aexit__(self, *exc):
        await self.close()

    # -- plumbing ----------------------------------------------------------
    async def connect(self, timeout=10):
        try:
            self.reader, self.writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port, ssl=self.ssl), timeout)
        except (OSError, asyncio.TimeoutError) as e:
            raise CastError("cannot connect to %s:%d: %s" % (self.host, self.port, e or "timed out"))
        self._tasks.append(asyncio.ensure_future(self._read_loop()))
        await self.virtual_connect(PLATFORM_ID)
        self._tasks.append(asyncio.ensure_future(self._heartbeat_loop()))

    async def close(self):
        for t in self._tasks:
            t.cancel()
        self._tasks = []
        if self.writer:
            for dest in list(self._connected):
                try:
                    self._send(NS_CONNECTION, {"type": "CLOSE"}, dest)
                except Exception:
                    pass
            try:
                await self.writer.drain()
            except Exception:
                pass
            self.writer.close()
            self.writer = None
        self.closed.set()

    def _send(self, namespace, payload, destination, source=None):
        if not self.writer:
            raise CastError("not connected")
        data = payload if isinstance(payload, str) else json.dumps(payload)
        self.writer.write(frame(encode_message(source or self.sender_id, destination, namespace, data)))

    async def send(self, namespace, payload, destination=PLATFORM_ID):
        self._send(namespace, payload, destination)
        await self.writer.drain()

    async def virtual_connect(self, destination):
        await self.send(NS_CONNECTION, {"type": "CONNECT"}, destination)
        self._connected.add(destination)

    async def request(self, namespace, payload, destination=PLATFORM_ID, timeout=10):
        """Send a message with a requestId and wait for the reply carrying the same id."""
        self._request_id += 1
        rid = self._request_id
        fut = asyncio.get_running_loop().create_future()
        self._waiters[rid] = fut
        try:
            await self.send(namespace, dict(payload, requestId=rid), destination)
            return await asyncio.wait_for(fut, timeout)
        except asyncio.TimeoutError:
            raise CastError("no answer to %s" % payload.get("type"))
        finally:
            self._waiters.pop(rid, None)

    async def _heartbeat_loop(self):
        try:
            while True:
                await asyncio.sleep(self.heartbeat)
                await self.send(NS_HEARTBEAT, {"type": "PING"}, PLATFORM_ID)
        except (asyncio.CancelledError, CastError, ConnectionError):
            pass

    async def _read_loop(self):
        try:
            while True:
                msg = decode_message(await read_frame(self.reader))
                await self._dispatch(msg)
        except (asyncio.IncompleteReadError, ConnectionError, ssl.SSLError):
            self.log("connection to the device closed")
        except asyncio.CancelledError:
            raise
        finally:
            self.closed.set()
            for fut in self._waiters.values():
                if not fut.done():
                    fut.set_exception(CastError("connection closed"))

    async def _dispatch(self, msg):
        if msg["payload"] is None:
            return
        try:
            body = json.loads(msg["payload"])
        except ValueError:
            return
        kind = body.get("type")
        if msg["namespace"] == NS_HEARTBEAT:
            if kind == "PING":                                       # answer the device's own pings
                self._send(NS_HEARTBEAT, {"type": "PONG"}, msg["source"], source=msg["destination"])
                await self.writer.drain()
            return
        if msg["namespace"] == NS_CONNECTION and kind == "CLOSE":
            self._connected.discard(msg["source"])
            self.log("device closed the virtual connection %s" % msg["source"])
            if msg["source"] == PLATFORM_ID:
                self.closed.set()
            return
        if kind == "RECEIVER_STATUS":
            self.receiver_status = body.get("status") or {}
        elif kind == "MEDIA_STATUS":
            entries = body.get("status") or []
            if entries:
                self.media_status = entries[0]
                if self.on_media_status:
                    self.on_media_status(self.media_status)
        rid = body.get("requestId")
        if rid in self._waiters and not self._waiters[rid].done():
            self._waiters[rid].set_result(body)

    # -- high level --------------------------------------------------------
    async def get_status(self):
        reply = await self.request(NS_RECEIVER, {"type": "GET_STATUS"})
        return reply.get("status") or {}

    async def launch(self, app_id=DEFAULT_MEDIA_RECEIVER, timeout=20):
        """Start an app and return its entry (appId, sessionId, transportId, ...). Opens a virtual connection to it."""
        reply = await self.request(NS_RECEIVER, {"type": "LAUNCH", "appId": app_id}, timeout=timeout)
        if reply.get("type") == "LAUNCH_ERROR":
            raise CastError("launch failed: %s" % reply.get("reason", "unknown"))
        deadline = asyncio.get_running_loop().time() + timeout
        while True:
            for app in (reply.get("status") or self.receiver_status).get("applications") or []:
                if app.get("appId") == app_id and app.get("transportId"):
                    await self.virtual_connect(app["transportId"])
                    return app
            if asyncio.get_running_loop().time() > deadline:
                raise CastError("the app did not start")
            await asyncio.sleep(0.3)
            reply = {"status": await self.get_status()}

    async def load(self, app, url, content_type, stream_type="LIVE", autoplay=True, timeout=30):
        """Play `url` in the running media app. Returns the first MEDIA_STATUS entry."""
        reply = await self.request(NS_MEDIA, {
            "type": "LOAD", "autoplay": autoplay, "currentTime": 0,
            "media": {"contentId": url, "contentType": content_type, "streamType": stream_type},
        }, destination=app["transportId"], timeout=timeout)
        if reply.get("type") in ("LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST", "INVALID_PLAYER_STATE"):
            raise CastError("%s: %s" % (reply["type"], reply.get("reason", "")))
        entries = reply.get("status") or []
        return entries[0] if entries else {}

    async def stop_app(self, app):
        try:
            await self.request(NS_RECEIVER, {"type": "STOP", "sessionId": app["sessionId"]}, timeout=5)
        except CastError:
            pass

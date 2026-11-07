#!/usr/bin/env python3
"""miracast-source: the Miracast (Wi-Fi Display) source engine.

Runs as the user. Listens on TCP 7236 for the TV, which connects to us once the
Wi-Fi Direct link is up (miracast-linkd provides that link), negotiates a video
format over RTSP (see wfd.py), then streams H.264 in MPEG-TS over RTP/UDP using
a GStreamer pipeline (a gst-launch-1.0 child process).

It is independent of how the link was made and of whatever started it:

  * input  : a listening socket, plus a few flags (--source, --resolution ...)
  * output : a JSON status file (default $XDG_RUNTIME_DIR/miracast-source.json)
             and the log on stderr

Sources:
  test    GStreamer test pattern (no portal, no permissions): proves the whole
          chain to the TV before real capture is involved
  portal  the screen, through the xdg-desktop-portal screencast (portal_capture.py)
  none    negotiate only, run no media process (tests)
"""

import argparse
import asyncio
import json
import os
import signal
import sys
import tempfile
import time

import wfd

SESSION_ID = "6B8B4567"
# The WFD spec fixes the transport-stream PIDs; some sinks only look there.
# GPU fit: scale with black borders into BGRx (borders in NV12 come out green on this
# driver), then convert to NV12, all in VA memory.
VA_FIT_TMPL = ["vapostproc", "add-borders=true", "!",
               "video/x-raw(memory:VAMemory),width=%(w)d,height=%(h)d,format=BGRx,pixel-aspect-ratio=1/1", "!",
               "vapostproc", "!", "video/x-raw(memory:VAMemory),format=NV12", "!"]
PID_VIDEO = 0x1011
PID_AUDIO = 0x1100
LEVEL_CAPS = {0x01: "3.1", 0x02: "3.2", 0x04: "4", 0x08: "4.1", 0x10: "4.2"}


def hw_encoder_available():
    """VA-API H.264 encoding usable here (plugin present and a render node exists)?"""
    import glob
    import subprocess
    if not glob.glob("/dev/dri/renderD*"):
        return False
    try:
        return subprocess.run(["gst-inspect-1.0", "vah264enc"], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=20).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def build_pipeline(args, mode, profile, level, sink_ip, client_port, server_port, portal_fd=None, portal_node=None,
                   audio_on=False, hw=False):
    """The gst-launch-1.0 argv for one stream. hw=True: scale/convert/encode on the GPU (VA-API)."""
    w, h, fps = mode["width"], mode["height"], mode["fps"]
    if args.source == "test":
        src = ["videotestsrc", "is-live=true", "pattern=ball", "!",
               "video/x-raw,width=%d,height=%d,framerate=%d/1" % (w, h, fps)]
    elif args.source == "portal":
        # The portal only delivers frames when something changes. provide-clock=false
        # is essential: pipewiresrc's own pipeline clock stalls on a static screen
        # and starves everything downstream (a black TV). With the system clock,
        # keepalive-time + videorate keep a steady stream; add-borders keeps the
        # aspect ratio when the screen is not 16:9.
        src = ["pipewiresrc", "fd=%d" % portal_fd, "path=%s" % portal_node, "do-timestamp=true",
               "always-copy=true", "provide-clock=false", "keepalive-time=100", "!",
               # xdph reports a bogus pixel-aspect-ratio (1/2147483647) which makes
               # videoscale stretch instead of letterbox; the pixels are square.
               # (capssetter directly behind pipewiresrc breaks its format negotiation
               # -- "target not found" -- so it must come after a videoconvert.)
               # Convert to I420 *before* scaling (half the bytes of BGRA), with threads,
               # and put queues between the stages so convert / scale / encode run on
               # different cores: this was 3.5x faster than one serial chain (1.3x -> 4.6x
               # real time in a benchmark) and is what stops the stream stuttering.
               "videoconvert", "n-threads=4", "!", "video/x-raw,format=I420", "!",
               "capssetter", "join=true", "replace=false", "caps=video/x-raw,pixel-aspect-ratio=1/1", "!",
               ] + ((["videorate", "!", "video/x-raw,framerate=%d/1" % fps, "!"] + [t % {"w": w, "h": h} for t in VA_FIT_TMPL]) if hw else
                    ["queue", "max-size-buffers=2", "leaky=downstream", "!",
                     "videoscale", "add-borders=true", "n-threads=4", "!", "videorate", "!",
                     "video/x-raw,width=%d,height=%d,framerate=%d/1,pixel-aspect-ratio=1/1" % (w, h, fps),
                     "!", "queue", "max-size-buffers=3", "leaky=downstream"])
    else:
        raise ValueError("no pipeline for source %r" % args.source)
    prof = "constrained-baseline" if profile == wfd.PROFILE_CBP else "high"
    enc_level = wfd.level_for_mode(mode, level)
    caps = "video/x-h264,profile=%s,level=(string)%s" % (prof, LEVEL_CAPS.get(enc_level, "4.1"))
    audio = []
    if audio_on:
        # system audio: the default sink's monitor, AAC-LC 48 kHz stereo in the same
        # transport stream. provide-clock=false for the same reason as the video.
        audio = ["pipewiresrc", "provide-clock=false", "do-timestamp=true",
                 "stream-properties=props,stream.capture.sink=true", "!",
                 "audio/x-raw,rate=48000,channels=2", "!", "audioconvert", "!", "audioresample", "!",
                 "fdkaacenc", "bitrate=128000", "!", "audio/mpeg,mpegversion=4,stream-format=adts", "!",
                 "aacparse", "!", "mux.sink_%d" % PID_AUDIO]
    if hw and args.source == "portal":
        enc = ["vah264enc", "rate-control=cbr", "bitrate=%d" % args.bitrate, "b-frames=0",
               "key-int-max=%d" % fps, "target-usage=7", "!", "video/x-h264,profile=%s" % prof, "!"]
        pre = []
    else:
        enc = ["x264enc", "tune=zerolatency", "speed-preset=ultrafast", "bitrate=%d" % args.bitrate,
               "key-int-max=%d" % fps, "bframes=0", "byte-stream=true", "!", caps, "!"]
        pre = ["!", "videoconvert", "!"] if args.source != "portal" else ["!"]
    return (["gst-launch-1.0", "-q"] + audio + src + pre + enc + [
        "h264parse", "config-interval=1", "!", "mux.sink_%d" % PID_VIDEO,
        "mpegtsmux", "name=mux", "alignment=7", "!",
        "rtpmp2tpay", "!",
        "udpsink", "host=%s" % sink_ip, "port=%d" % client_port, "bind-port=%d" % server_port, "sync=false",
    ])


class Status:
    """JSON status file other programs (CLI, Quickshell) can read."""

    def __init__(self, path):
        self.path = path
        self.data = {"state": "starting", "error": ""}

    def set(self, **kw):
        self.data.update(kw)
        self.data["updated"] = time.time()
        d = os.path.dirname(self.path) or "."
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".status-")
        with os.fdopen(fd, "w") as f:
            json.dump(self.data, f)
        os.chmod(tmp, 0o644)
        os.replace(tmp, self.path)


class Session:
    """One TV, one connection."""

    def __init__(self, args, status, reader, writer, loop, capture=None):
        self.args = args
        self.status = status
        self.reader = reader
        self.writer = writer
        self.loop = loop
        self.cseq = 0
        self.pending = {}                     # cseq -> Future
        self.sink_ip = writer.get_extra_info("peername")[0]
        self.local_ip = writer.get_extra_info("sockname")[0]
        self.client_port = None
        self.mode = None
        self.profile = None
        self.level = None
        self.proc = None
        self.done = loop.create_future()
        self.playing = False
        self.capture = capture            # portal screencast chosen before the TV connected, or None

    # --- plumbing ------------------------------------------------------
    def log(self, msg):
        print("[%s] %s" % (self.sink_ip, msg), file=sys.stderr, flush=True)

    def send(self, data):
        self.writer.write(data)

    async def request(self, method, uri, headers=None, body="", timeout=10):
        self.cseq += 1
        fut = self.loop.create_future()
        self.pending[self.cseq] = fut
        self.send(wfd.build_request(method, uri, self.cseq, headers, body))
        await self.writer.drain()
        try:
            return await asyncio.wait_for(fut, timeout)
        except asyncio.TimeoutError:
            raise wfd.RtspError("no response to %s" % method)
        finally:
            self.pending.pop(self.cseq, None)

    async def read_loop(self):
        buf = b""
        try:
            while True:
                chunk = await self.reader.read(65536)
                if not chunk:
                    break
                buf += chunk
                while True:
                    n = wfd.message_length(buf)
                    if n is None:
                        break
                    raw, buf = buf[:n], buf[n:]
                    await self.dispatch(wfd.parse_message(raw.decode("utf-8", "replace")))
        except (wfd.RtspError, ConnectionError) as e:
            self.log("connection ended: %s" % e)
        finally:
            if not self.done.done():
                self.done.set_result("sink closed the connection")

    async def dispatch(self, m):
        if m.is_response:
            fut = self.pending.get(m.cseq)
            if fut and not fut.done():
                fut.set_result(m)
            return
        self.log("<- %s" % m.start)
        handler = {
            "OPTIONS": self.on_options, "SETUP": self.on_setup, "PLAY": self.on_play,
            "PAUSE": self.on_pause, "TEARDOWN": self.on_teardown,
            "GET_PARAMETER": self.on_get_parameter, "SET_PARAMETER": self.on_set_parameter,
        }.get(m.method)
        if handler is None:
            self.send(wfd.build_response(m.cseq or 0, 405, "Method Not Allowed"))
        else:
            await handler(m)
        await self.writer.drain()

    # --- requests from the sink ----------------------------------------
    async def on_options(self, m):                       # M2
        self.send(wfd.build_response(m.cseq, headers={"Public": wfd.PUBLIC_M2}))

    async def on_get_parameter(self, m):                 # M16 keep-alive
        self.send(wfd.build_response(m.cseq))

    async def on_set_parameter(self, m):
        p = wfd.parse_params(m.body)
        if "wfd_idr_request" in p:
            self.log("sink asked for an IDR frame (next keyframe is within 1s)")
        self.send(wfd.build_response(m.cseq))

    async def on_setup(self, m):                         # M6
        try:
            self.client_port = wfd.parse_transport_client_port(m.headers.get("transport", ""))
        except wfd.RtspError as e:
            self.send(wfd.build_response(m.cseq, 400, "Bad Request"))
            self.log("bad SETUP: %s" % e)
            return
        transport = "RTP/AVP/UDP;unicast;client_port=%d;server_port=%d" % (self.client_port, self.args.rtp_port)
        self.send(wfd.build_response(m.cseq, headers={
            "Session": "%s;timeout=60" % SESSION_ID, "Transport": transport}))
        self.status.set(state="setup", client_port=self.client_port)

    async def on_play(self, m):                          # M7
        self.send(wfd.build_response(m.cseq, headers={"Session": SESSION_ID}))
        await self.writer.drain()
        await self.start_stream()

    async def on_pause(self, m):
        self.send(wfd.build_response(m.cseq, headers={"Session": SESSION_ID}))

    async def on_teardown(self, m):                      # M8
        self.send(wfd.build_response(m.cseq, headers={"Session": SESSION_ID}))
        await self.writer.drain()
        if not self.done.done():
            self.done.set_result("sink sent TEARDOWN")

    # --- negotiation (we are the RTSP client here) ----------------------
    async def negotiate(self):
        self.status.set(state="negotiating", sink_ip=self.sink_ip, local_ip=self.local_ip, error="")
        r = await self.request("OPTIONS", "*", {"Require": "org.wfa.wfd1.0"})          # M1
        if r.status != 200:
            raise wfd.RtspError("M1 rejected: %s" % r.start)
        r = await self.request("GET_PARAMETER", "rtsp://localhost/wfd1.0",              # M3
                               {"Content-Type": "text/parameters"}, wfd.M3_QUERY)
        if r.status != 200:
            raise wfd.RtspError("M3 rejected: %s" % r.start)
        caps = wfd.parse_params(r.body)
        self.log("sink capabilities: %s" % json.dumps(caps))
        entries = wfd.parse_video_formats(caps.get("wfd_video_formats", "none"))
        choice = wfd.choose_video(entries, self.args.preference, strict=self.args.strict_levels)
        if not choice:
            raise wfd.RtspError("sink offers no video format we can encode")
        self.profile, self.level, bit = choice
        self.mode = wfd.mode_of(bit)
        ports = caps.get("wfd_client_rtp_ports", "RTP/AVP/UDP;unicast 19000 0 mode=play")
        self.audio = (self.args.source == "portal" and not self.args.no_audio and
                      wfd.choose_audio(caps.get("wfd_audio_codecs")) != "none")
        body = wfd.build_m4_body(self.local_ip, ports, wfd.format_video_selection(*choice),
                                 wfd.choose_audio(caps.get("wfd_audio_codecs")) if self.audio else "none")
        r = await self.request("SET_PARAMETER", "rtsp://localhost/wfd1.0",              # M4
                               {"Content-Type": "text/parameters"}, body)
        if r.status != 200:
            raise wfd.RtspError("M4 rejected: %s (%s)" % (r.start, r.body.strip()))
        self.status.set(state="ready", mode=self.mode, profile=self.profile, level=self.level)
        r = await self.request("SET_PARAMETER", "rtsp://localhost/wfd1.0",              # M5
                               {"Content-Type": "text/parameters"}, "wfd_trigger_method: SETUP\r\n")
        if r.status != 200:
            raise wfd.RtspError("M5 rejected: %s" % r.start)
        self.log("negotiated %dx%d@%d, now waiting for the sink's SETUP and PLAY" %
                 (self.mode["width"], self.mode["height"], self.mode["fps"]))

    # --- streaming -----------------------------------------------------
    def use_hw(self):
        enc = self.args.encoder
        hw = enc == "va" or (enc == "auto" and self.args.source == "portal" and hw_encoder_available())
        self.log("encoder: %s" % ("VA-API (GPU)" if hw else "x264 (CPU)"))
        return hw

    async def start_stream(self):
        if self.playing:
            return
        self.playing = True
        if self.args.source == "none":
            self.status.set(state="streaming", pipeline="none")
            return
        portal_fd = self.capture.fd if self.capture else None
        portal_node = self.capture.node if self.capture else None
        cmd = build_pipeline(self.args, self.mode, self.profile, self.level, self.sink_ip,
                             self.client_port, self.args.rtp_port, portal_fd, portal_node,
                             audio_on=getattr(self, "audio", False), hw=self.use_hw())
        self.log("starting: %s" % " ".join(cmd))
        pass_fds = (portal_fd,) if portal_fd is not None else ()
        self.proc = await asyncio.create_subprocess_exec(*cmd, stderr=asyncio.subprocess.PIPE, pass_fds=pass_fds)
        self.status.set(state="streaming", pipeline=" ".join(cmd))
        asyncio.ensure_future(self.watch_proc())

    async def watch_proc(self):
        err = await self.proc.stderr.read()
        code = await self.proc.wait()
        if not self.done.done():
            self.log("pipeline exited (%s): %s" % (code, err.decode(errors="replace").strip()[-400:]))
            self.status.set(state="error", error="pipeline exited (%s): %s" % (code, err.decode(errors="replace").strip()[-300:]))
            self.done.set_result("pipeline exited")

    async def stop_stream(self):
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()
            try:
                await asyncio.wait_for(self.proc.wait(), 3)
            except asyncio.TimeoutError:
                self.proc.kill()
        if self.capture:
            await self.capture.close()
            self.capture = None

    # --- lifecycle -----------------------------------------------------
    async def run(self):
        reader_task = asyncio.ensure_future(self.read_loop())
        try:
            await self.negotiate()
        except (wfd.RtspError, ConnectionError, asyncio.TimeoutError) as e:
            self.log("negotiation failed: %s" % e)
            self.status.set(state="error", error=str(e))
            if not self.done.done():
                self.done.set_result("negotiation failed")
        reason = await self.done
        self.log("session over: %s" % reason)
        await self.stop_stream()
        reader_task.cancel()
        self.writer.close()
        if self.status.data.get("state") != "error":
            self.status.set(state="ended", reason=reason)
        return reason


def read_link(path):
    try:
        with open(path) as f:
            return json.load(f).get("link", {})
    except (OSError, ValueError):
        return {}


async def peer_allowed(args, ip):
    """Only the TV we are linked to may connect (the socket listens on all
    interfaces). Waits a few seconds: the TV can connect the moment the group
    forms, a beat before the daemon has recorded its address."""
    if not args.link_state:
        return True
    deadline = time.time() + args.link_wait
    while True:
        link = read_link(args.link_state)
        if link.get("state") == "ready" and link.get("remote_ip") == ip:
            return True
        if time.time() >= deadline:
            print("refusing %s: link is %s (remote %s)" % (ip, link.get("state"), link.get("remote_ip")),
                  file=sys.stderr, flush=True)
            return False
        await asyncio.sleep(0.25)


async def serve(args):
    loop = asyncio.get_running_loop()
    status = Status(args.status_file)
    got_conn = loop.create_future()

    async def on_connect(reader, writer):
        if got_conn.done() or not await peer_allowed(args, writer.get_extra_info("peername")[0]):
            writer.close()                       # one TV at a time, and only the linked one
            return
        got_conn.set_result(None)
        await Session(args, status, reader, writer, loop, capture).run()
        finished.set()

    finished = asyncio.Event()
    capture = None
    if args.source == "portal":
        # Ask what to share *first*. The TV gives up within seconds if the stream
        # is slow to start after PLAY, and the picker waits for a human.
        import portal_capture
        status.set(state="choosing", note="pick what to share", source=args.source, error="")
        try:
            capture = await portal_capture.open_screencast(loop, lambda m: print(m, file=sys.stderr, flush=True))
        except Exception as e:  # noqa: BLE001  (CaptureError, D-Bus errors)
            print("screen capture failed: %s" % e, file=sys.stderr, flush=True)
            status.set(state="error", error="screen capture failed: %s" % e)
            return 1
    server = await asyncio.start_server(on_connect, args.listen, args.port)
    status.set(state="listening", port=args.port, source=args.source, error="", note="")
    print("miracast-source listening on %s:%d (source=%s)" % (args.listen, args.port, args.source),
          file=sys.stderr, flush=True)
    stop = loop.create_future()
    for s in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(s, lambda: stop.done() or stop.set_result(None))
    stopper = asyncio.ensure_future(stop)
    connected = asyncio.ensure_future(asyncio.shield(got_conn))
    # The idle timeout is only for waiting for a TV to show up. Once one has
    # connected the session runs until it ends or we are told to stop; applying
    # the timeout to the whole run cut every stream off after exactly that long.
    done, _ = await asyncio.wait({connected, stopper}, return_when=asyncio.FIRST_COMPLETED,
                                 timeout=args.idle_timeout or None)
    if not done:
        status.set(state="ended", reason="no TV connected within %ds" % args.idle_timeout)
    elif connected in done:
        await asyncio.wait({asyncio.ensure_future(finished.wait()), stopper}, return_when=asyncio.FIRST_COMPLETED)
    server.close()
    if capture:
        await capture.close()
    return 0


def main(argv=None):
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--listen", default="0.0.0.0")
    p.add_argument("--port", type=int, default=7236, help="RTSP control port (must match the daemon's WFD IE)")
    p.add_argument("--rtp-port", type=int, default=5000, help="our UDP source port for the stream")
    p.add_argument("--source", choices=["test", "portal", "none"], default="test")
    p.add_argument("--encoder", choices=["auto", "va", "x264"], default="x264",
                   help="H.264 encoder. x264 (CPU) is the default; 'va' = VA-API on the GPU and 'auto' = va when "
                        "available are experimental: frames from a PipeWire source came out flat in testing")
    p.add_argument("--no-audio", action="store_true", help="do not send system audio (portal source only)")
    p.add_argument("--strict-levels", action="store_true",
                   help="only pick modes the sink's advertised H.264 level can carry (the Fire TV advertises 1080p30 at level 3.1 and decodes it fine)")
    p.add_argument("--bitrate", type=int, default=12000, help="video bitrate, kbit/s")
    p.add_argument("--preference", type=lambda s: [int(x) for x in s.split(",")], default=None,
                   help="CEA mode bits to try, best first (default 7,5,6,8,1,0 = 1080p30, 720p30, ...)")
    p.add_argument("--link-state", default=None,
                   help="miracast-linkd's state.json: accept only the TV the link is up with")
    p.add_argument("--link-wait", type=float, default=8.0, help="seconds to wait for the link to become ready")
    p.add_argument("--status-file", default=os.path.join(runtime, "miracast-source.json"))
    p.add_argument("--idle-timeout", type=int, default=0, help="exit if no TV connects within N seconds (0 = never)")
    args = p.parse_args(argv)
    return asyncio.run(serve(args))


if __name__ == "__main__":
    sys.exit(main())

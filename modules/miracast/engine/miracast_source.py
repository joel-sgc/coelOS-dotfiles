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
# GStreamer colorimetry strings (range:matrix:transfer:primaries). The stream is tagged with these
# in the H.264 VUI and the RGB->YUV conversion uses the matching matrix.
COLORIMETRY = {"bt709": "bt709", "bt709-full": "1:3:5:1", "bt601": "bt601"}
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


def build_audio_chain(args):
    """System audio (the default sink's monitor) or silence, encoded as AAC-LC 48 kHz stereo ADTS."""
    src = (["audiotestsrc", "is-live=true", "wave=silence"] if (args.source in ("test", "testcap") or
                                                               args.audio_source == "silence") else
           ["pipewiresrc", "provide-clock=false", "do-timestamp=true",
            "stream-properties=props,stream.capture.sink=true"])
    return src + ["!", "audio/x-raw,rate=48000,channels=2", "!", "audioconvert", "!", "audioresample", "!",
                  "fdkaacenc", "bitrate=128000", "!", "audio/mpeg,mpegversion=4,stream-format=adts"]


def build_audio_cmd(args):
    """The audio capture process: AAC ADTS on stdout, read by the main pipeline's fdsrc."""
    return ["gst-launch-1.0", "-q"] + build_audio_chain(args) + ["!", "fdsink", "fd=1"]


def build_pipeline(args, mode, profile, level, sink_ip, client_port, server_port, portal_fd=None, portal_node=None,
                   audio_on=False, hw=False, audio_fd=None):
    """The gst-launch-1.0 argv for one stream. hw=True: scale/convert/encode on the GPU (VA-API)."""
    w, h, fps = mode["width"], mode["height"], mode["fps"]
    skip = set(filter(None, (getattr(args, "chain_skip", "") or "").split(",")))   # diagnostics only
    if "all" in skip:
        skip |= {"capssetter", "queues", "lanczos", "videorate"}
    if args.source == "test":
        src = ["videotestsrc", "is-live=true", "pattern=%s" % args.pattern, "!",
               "video/x-raw,width=%d,height=%d,framerate=%d/1" % (w, h, fps)]
    elif args.source in ("portal", "testcap"):
        # The portal only delivers frames when something changes. provide-clock=false
        # is essential: pipewiresrc's own pipeline clock stalls on a static screen
        # and starves everything downstream (a black TV). With the system clock,
        # keepalive-time + videorate keep a steady stream; add-borders keeps the
        # aspect ratio when the screen is not 16:9.
        # "testcap" (diagnostic): a synthetic 2256x1504 BGRA picture through exactly the same chain,
        # to tell chain problems apart from screen-capture problems.
        head = (["videotestsrc", "is-live=true", "pattern=%s" % args.pattern, "!",
                 "video/x-raw,format=%s,width=%s,height=%s,framerate=30/1,pixel-aspect-ratio=1/2147483647" % (
                     (args.cap_format,) + tuple(args.cap_size.split("x"))), "!"]
                if args.source == "testcap" else
                ["pipewiresrc", "fd=%d" % portal_fd, "path=%s" % portal_node, "do-timestamp=true",
                 "always-copy=true", "provide-clock=false", "keepalive-time=100", "!"])
        src = head + [
               # xdph reports a bogus pixel-aspect-ratio (1/2147483647) which makes
               # videoscale stretch instead of letterbox; the pixels are square.
               # (capssetter directly behind pipewiresrc breaks its format negotiation
               # -- "target not found" -- so it must come after a videoconvert.)
               # Scale in the original (RGB) colour format and convert to I420 only at the end:
               # converting to I420 first subsamples colour at full size and then scales it again,
               # which looked faded and soft. Queues between the stages let convert / scale / encode
               # run on separate cores (the serial chain only managed ~1.1x real time).
               "videoconvert", "!",
               ] + (["capssetter", "join=true", "replace=false", "caps=video/x-raw,pixel-aspect-ratio=1/1", "!"]
                    if "capssetter" not in skip else [])
        if hw:
            src += ["videorate", "!", "video/x-raw,framerate=%d/1" % fps, "!"] + [t % {"w": w, "h": h} for t in VA_FIT_TMPL]
        else:
            if "queues" not in skip:
                src += ["queue", "max-size-buffers=2", "leaky=downstream", "!"]
            src += ["videoscale"]
            if "lanczos" not in skip:
                src += ["method=lanczos"]
            src += ["add-borders=true", "n-threads=4", "!"]
            if "videorate" not in skip:
                src += ["videorate", "!"]
            src += ["video/x-raw,width=%d,height=%d,framerate=%d/1,pixel-aspect-ratio=1/1" % (w, h, fps)]
            if "queues" not in skip:
                src += ["!", "queue", "max-size-buffers=3", "leaky=downstream"]
    else:
        raise ValueError("no pipeline for source %r" % args.source)
    prof = "constrained-baseline" if profile == wfd.PROFILE_CBP else "high"
    enc_level = wfd.level_for_mode(mode, level)
    caps = "video/x-h264,profile=%s,level=(string)%s" % (prof, LEVEL_CAPS.get(enc_level, "4.1"))
    audio = []
    if audio_on:
        if audio_fd is not None:
            # AAC arrives from a separate capture process (build_audio_cmd) started a little after the
            # video, through a pipe; timestamps are the arrival time.
            audio = ["fdsrc", "fd=%d" % audio_fd, "do-timestamp=true", "blocksize=4096", "!",
                     "aacparse", "!", "mux.sink_%d" % PID_AUDIO]
        else:
            audio = build_audio_chain(args) + ["!", "aacparse", "!", "mux.sink_%d" % PID_AUDIO]
    if hw and args.source == "portal":
        enc = ["vah264enc", "rate-control=cbr", "bitrate=%d" % args.bitrate, "b-frames=0",
               "key-int-max=%d" % fps, "target-usage=7", "!", "video/x-h264,profile=%s" % prof, "!"]
        pre = []
    else:
        enc = ["x264enc", "tune=zerolatency", "speed-preset=%s" % args.preset, "bitrate=%d" % args.bitrate,
               "key-int-max=%d" % fps, "bframes=0", "byte-stream=true"] + (
                   ["vbv-buf-capacity=%d" % args.vbv_ms] if args.vbv_ms else []) + ["!", caps, "!"]
        pre = ["!", "videoconvert", "n-threads=4", "!",
               "video/x-raw,format=I420,colorimetry=%s" % COLORIMETRY[args.color], "!"]
        # optional look adjustment (the TV's picture can look flat next to the laptop panel)
        if args.gamma != 1.0:
            pre += ["gamma", "gamma=%g" % args.gamma, "!"]
        if (args.contrast, args.saturation, args.brightness) != (1.0, 1.0, 0.0):
            pre += ["videobalance", "contrast=%g" % args.contrast, "saturation=%g" % args.saturation,
                    "brightness=%g" % args.brightness, "!"]
    return (["gst-launch-1.0", "-q"] + audio + src + pre + enc + [
        "h264parse", "config-interval=-1", "!", "mux.sink_%d" % PID_VIDEO,
        "mpegtsmux", "name=mux", "alignment=7"] + ([] if args.no_ts_spec else [
            # Wi-Fi Display spec: PMT on PID 0x100, PAT/PMT repeated at most every 100 ms (we use 50 ms),
            # PCR carried by the video PID (mpegtsmux cannot make a PCR-only PID 0x1000).
            "pat-interval=4500", "pmt-interval=4500", "pcr-interval=2700",
            "prog-map=prog_map,sink_%d=(int)1,sink_%d=(int)1,PMT_1=(uint)256,PCR_1=sink_%d" % (
                PID_VIDEO, PID_AUDIO, PID_VIDEO)]) + (
            ["bitrate=%d" % (args.mux_bitrate * 1000)] if args.mux_bitrate else []) + ["!",
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
        self.got_m2 = asyncio.Event()
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
        except Exception:                              # a bug in a handler must not look like the TV hanging up
            import traceback
            self.log("internal error: %s" % traceback.format_exc().strip().replace("\n", " | "))
            self.status.set(state="error", error="internal error (see logs)")
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
        self.got_m2.set()

    async def on_get_parameter(self, m):                 # M16 keep-alive
        self.send(wfd.build_response(m.cseq))

    async def on_set_parameter(self, m):
        p = wfd.parse_params(m.body)
        if "wfd_idr_request" in p:
            self.log("sink asked for an IDR frame (next keyframe is within 1s)")
        self.send(wfd.build_response(m.cseq))

    async def on_setup(self, m):                         # M6
        self.log("SETUP headers: %s" % dict(m.headers))
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
        # Strict sinks (Roku) answer M3 with "455 Method Not Valid In This State" until their own
        # M2 (OPTIONS) has been answered; the Fire TV is lenient. Wait for it, but don't hang on a sink
        # that never sends one.
        try:
            await asyncio.wait_for(self.got_m2.wait(), 5)
        except asyncio.TimeoutError:
            self.log("sink sent no M2; continuing")
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
        self.audio = (self.args.source in ("portal", "test", "testcap") and not self.args.no_audio and
                      wfd.choose_audio(caps.get("wfd_audio_codecs")) != "none")
        body = wfd.build_m4_body(self.local_ip, ports, wfd.format_video_selection(*choice),
                                 wfd.choose_audio(caps.get("wfd_audio_codecs")) if self.audio else "none",
                                 content_protection="none" if caps.get("wfd_content_protection", "none")
                                 .strip().lower() not in ("none", "") else None)
        self.log("M4: %s" % body.strip().replace("\r\n", " | "))
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
        audio_on = getattr(self, "audio", False) and self.args.audio_source != "off"
        pipe_r = pipe_w = None
        if audio_on:
            pipe_r, pipe_w = os.pipe()
            os.set_inheritable(pipe_r, True)
        cmd = build_pipeline(self.args, self.mode, self.profile, self.level, self.sink_ip,
                             self.client_port, self.args.rtp_port, portal_fd, portal_node,
                             audio_on=audio_on, hw=self.use_hw(), audio_fd=pipe_r)
        self.log("starting: %s" % " ".join(cmd))
        pass_fds = tuple(fd for fd in (portal_fd, pipe_r) if fd is not None)
        self.proc = await asyncio.create_subprocess_exec(*cmd, stderr=asyncio.subprocess.PIPE, pass_fds=pass_fds)
        if audio_on:
            os.close(pipe_r)
            self.audio_task = asyncio.ensure_future(self.start_audio(pipe_w))
        self.status.set(state="streaming", pipeline=" ".join(cmd))
        asyncio.ensure_future(self.watch_proc())
        self.keepalive_task = asyncio.ensure_future(self.keepalive())

    async def start_audio(self, pipe_w):
        """Start the audio capture shortly after the video pipeline. The Roku shows black when the stream
        begins with audio (verified: identical streams differing only by this start order); a stream that
        begins with video plays. Audio timestamps are arrival times, so lip-sync is unaffected."""
        try:
            await asyncio.sleep(self.args.audio_start_delay_ms / 1000.0)
            cmd = build_audio_cmd(self.args)
            self.log("audio: %s" % " ".join(cmd))
            self.audio_proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=pipe_w, stderr=asyncio.subprocess.DEVNULL)
        except asyncio.CancelledError:
            pass
        finally:
            os.close(pipe_w)

    async def keepalive(self):
        """M16: the source sends GET_PARAMETER every ~25 s (the SETUP reply promises timeout=60). Strict
        sinks (Roku) tear the session down after exactly 60 s without it; the Fire TV never cared."""
        try:
            while not self.done.done():
                await asyncio.sleep(25)
                if self.done.done():
                    break
                try:
                    await self.request("GET_PARAMETER", "rtsp://localhost/wfd1.0", {"Session": SESSION_ID})
                except wfd.RtspError as e:
                    self.log("keep-alive: %s" % e)
        except asyncio.CancelledError:
            pass

    async def watch_proc(self):
        err = await self.proc.stderr.read()
        code = await self.proc.wait()
        if not self.done.done():
            self.log("pipeline exited (%s): %s" % (code, err.decode(errors="replace").strip()[-400:]))
            self.status.set(state="error", error="pipeline exited (%s): %s" % (code, err.decode(errors="replace").strip()[-300:]))
            self.done.set_result("pipeline exited")

    async def stop_stream(self):
        task = getattr(self, "audio_task", None)
        if task:
            task.cancel()
        ap = getattr(self, "audio_proc", None)
        if ap and ap.returncode is None:
            ap.terminate()
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


def build_parser():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--listen", default="0.0.0.0")
    p.add_argument("--port", type=int, default=7236, help="RTSP control port (must match the daemon's WFD IE)")
    p.add_argument("--rtp-port", type=int, default=5000, help="our UDP source port for the stream")
    p.add_argument("--source", choices=["test", "testcap", "portal", "none"], default="test")
    p.add_argument("--encoder", choices=["auto", "va", "x264"], default="x264",
                   help="H.264 encoder. x264 (CPU) is the default; 'va' = VA-API on the GPU and 'auto' = va when "
                        "available are experimental: frames from a PipeWire source came out flat in testing")
    p.add_argument("--vbv-ms", type=int, default=30,
                   help="x264 rate-control buffer in ms (0 = x264 default, 600). Small = keyframes cannot be "
                        "huge, so no big packet bursts over Wi-Fi Direct (default 30)")
    p.add_argument("--mux-bitrate", type=int, default=0,
                   help="pad the transport stream with null packets up to this constant rate (kbit/s). A mostly "
                        "static screen produces almost no data and some sinks never start playing; 0 = off")
    p.add_argument("--chain-skip", default="",
                   help="diagnostics: comma list of capture-chain stages to leave out "
                        "(capssetter, queues, lanczos, videorate)")
    p.add_argument("--cap-format", default="BGRA", help="diagnostics (--source testcap): pixel format of the fake capture")
    p.add_argument("--cap-size", default="2256x1504", help="diagnostics (--source testcap): size of the fake capture")
    p.add_argument("--audio-start-delay-ms", type=int, default=1000,
                   help="start the audio capture this many ms after the video pipeline so the stream begins "
                        "with video (the Roku shows black otherwise)")
    p.add_argument("--no-ts-spec", action="store_true",
                   help="do not apply the Wi-Fi Display transport-stream layout (PMT PID 0x100, PAT/PMT every 50 ms, "
                        "PCR on the video PID)")
    p.add_argument("--audio-source", choices=["system", "silence", "off"], default="system",
                   help="what to send as audio: the speakers' monitor (default), silence, or 'off' = AAC is "
                        "negotiated (the Roku stops answering if told 'no audio') but no audio is sent (diagnostics)")
    p.add_argument("--color", choices=sorted(COLORIMETRY), default="bt709",
                   help="how the picture is encoded/tagged: bt709 (HD standard, limited range; what the TVs "
                        "decode as), bt709-full or bt601. The Fire TV ignores the tags and always uses bt709")
    p.add_argument("--pattern", default="ball",
                   help="videotestsrc pattern for --source test (e.g. ball, smpte, colors, gradient)")
    p.add_argument("--preset", default="veryfast",
                   help="x264 speed preset; slower = sharper at the same bitrate (ultrafast turns the deblocking filter off)")
    p.add_argument("--contrast", type=float, default=1.0, help="1.0 = unchanged (range 0-2)")
    p.add_argument("--saturation", type=float, default=1.0, help="1.0 = unchanged (range 0-2)")
    p.add_argument("--brightness", type=float, default=0.0, help="0.0 = unchanged (range -1..1)")
    p.add_argument("--gamma", type=float, default=1.0, help="1.0 = unchanged; >1 brightens midtones (0.01-10)")
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
    return p


def main(argv=None):
    p = build_parser()
    args = p.parse_args(argv)
    return asyncio.run(serve(args))


if __name__ == "__main__":
    sys.exit(main())

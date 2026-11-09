#!/usr/bin/env python3
"""Cast the screen to a Google Cast device (Chromecast, Google TV, Nest speakers/displays, Cast-enabled TVs).

How: this is *not* Chrome's low-latency mirroring (the Cast Streaming protocol) -- it is the portable route every
Cast device supports. We encode the screen to a live HLS stream (H.264 + AAC, 1 s MPEG-TS segments), serve it over HTTP
to the device and tell the Default Media Receiver to play it. Expect 3-6 s of delay: fine for video and slides, not
for interactive use.

    gcast_engine.py --host 192.168.0.50 --name "Living Room" --source portal

  input  : a Cast device address, a source (portal = the screen via xdg-desktop-portal, test = a test pattern)
  output : a JSON status file ($XDG_RUNTIME_DIR/gcast-source.json) and the log on stderr
"""

import argparse
import asyncio
import json
import os
import shutil
import signal
import sys
import tempfile
import time

_here = os.path.dirname(os.path.abspath(__file__))
_castlib = os.path.join(_here, "..", "..", "castlib")           # shared capture code (Nix puts it on PYTHONPATH)
if os.path.isdir(_castlib):
    sys.path.insert(0, _castlib)

import castv2  # noqa: E402
import hls  # noqa: E402

RESOLUTIONS = {"1080p": (1920, 1080), "720p": (1280, 720)}


class Status:
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


def build_pipeline(args, directory, portal_fd=None, portal_node=None):
    """gst-launch argv: screen (or test pattern) + audio -> H.264/AAC -> hlssink2 (live.m3u8 + seg*.ts in `directory`)."""
    w, h = RESOLUTIONS[args.resolution]
    fps = args.fps
    if args.source == "test":
        video = ["videotestsrc", "is-live=true", "pattern=%s" % args.pattern, "!",
                 "video/x-raw,width=%d,height=%d,framerate=%d/1" % (w, h, fps)]
        audio_src = ["audiotestsrc", "is-live=true", "wave=%s" % ("sine" if args.audio_source == "tone" else "silence"),
                     "volume=0.2"]
    elif args.source == "portal":
        # Same lessons as the Miracast engine: pipewiresrc must not provide the clock (it stalls on a static screen),
        # videoconvert before capssetter (xdph's pixel-aspect-ratio is bogus), fit with borders, queues between stages.
        video = ["pipewiresrc", "fd=%d" % portal_fd, "path=%s" % portal_node, "do-timestamp=true",
                 "always-copy=true", "provide-clock=false", "keepalive-time=100", "!",
                 "videoconvert", "!",
                 "capssetter", "join=true", "replace=false", "caps=video/x-raw,pixel-aspect-ratio=1/1", "!",
                 "queue", "max-size-buffers=2", "leaky=downstream", "!",
                 "videoscale", "method=lanczos", "add-borders=true", "n-threads=4", "!", "videorate", "!",
                 "video/x-raw,width=%d,height=%d,framerate=%d/1,pixel-aspect-ratio=1/1" % (w, h, fps), "!",
                 "queue", "max-size-buffers=3", "leaky=downstream"]
        audio_src = ["pipewiresrc", "provide-clock=false", "do-timestamp=true",
                     "stream-properties=props,stream.capture.sink=true"]
    else:
        raise ValueError("no pipeline for source %r" % args.source)
    gop = max(1, int(fps * args.segment_seconds))
    pipeline = ["gst-launch-1.0", "-q",
                "hlssink2", "name=hls", "location=%s" % os.path.join(directory, "seg%05d.ts"),
                "playlist-location=%s" % os.path.join(directory, "live.m3u8"),
                "target-duration=%d" % max(1, round(args.segment_seconds)), "max-files=8", "playlist-length=4"]
    pipeline += video + ["!", "videoconvert", "n-threads=4", "!", "video/x-raw,format=I420,colorimetry=bt709", "!",
                         "x264enc", "tune=zerolatency", "speed-preset=%s" % args.preset, "bitrate=%d" % args.bitrate,
                         "key-int-max=%d" % gop, "bframes=0", "byte-stream=true",
                         "vbv-buf-capacity=%d" % args.vbv_ms, "!",
                         "video/x-h264,profile=high,level=(string)4.1", "!",
                         "h264parse", "config-interval=-1", "!", "hls.video"]
    if not args.no_audio:
        pipeline += audio_src + ["!", "audio/x-raw,rate=48000,channels=2", "!", "audioconvert", "!", "audioresample", "!",
                                 "fdkaacenc", "bitrate=128000", "!", "audio/mpeg,mpegversion=4,stream-format=adts", "!",
                                 "aacparse", "!", "hls.audio"]
    return pipeline


async def run(args, status):
    loop = asyncio.get_running_loop()
    log = lambda m: print(m, file=sys.stderr, flush=True)    # noqa: E731
    stop = loop.create_future()
    for s in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(s, lambda: stop.done() or stop.set_result("stopped"))

    capture = None
    proc = server = cast = app = None
    workdir = tempfile.mkdtemp(prefix="gcast-", dir=os.environ.get("XDG_RUNTIME_DIR") or None)
    try:
        if args.source == "portal":
            import portal_capture
            status.set(state="choosing", note="pick what to share", device=args.name or args.host)
            capture = await portal_capture.open_screencast(loop, log)
        status.set(state="preparing", note="", device=args.name or args.host)
        host_ip = args.advertise_ip or hls.local_ip_for(args.host)
        server = await hls.HlsServer(workdir, allowed_ip=None if args.any_client else args.host,
                                     port=args.http_port, log=log).start()
        cmd = build_pipeline(args, workdir, capture.fd if capture else None, capture.node if capture else None)
        log("starting: %s" % " ".join(cmd))
        proc = await asyncio.create_subprocess_exec(*cmd, stderr=asyncio.subprocess.PIPE,
                                                    pass_fds=(capture.fd,) if capture else ())
        proc_exit = asyncio.ensure_future(proc.wait())
        deadline = loop.time() + args.ready_timeout
        while not hls.wait_ready(workdir, 2):
            if proc_exit.done():
                err = (await proc.stderr.read()).decode(errors="replace").strip()[-400:]
                raise RuntimeError("encoder exited (%s): %s" % (proc.returncode, err))
            if loop.time() > deadline:
                raise RuntimeError("the encoder produced no stream within %ds" % args.ready_timeout)
            await asyncio.sleep(0.25)
        url = server.url(host_ip)
        log("stream ready: %s" % url)

        status.set(state="connecting", url=url)
        cast = castv2.CastClient(args.host, args.port, log=log)
        await cast.connect()
        app = await cast.launch(args.app_id)
        log("launched %s (%s)" % (app.get("displayName"), app.get("appId")))
        status.set(state="loading", app=app.get("displayName"))
        first = await cast.load(app, url, "application/x-mpegURL", stream_type="LIVE")
        player = {"state": first.get("playerState", "?")}
        status.set(state="casting", player=player["state"], url=url)
        log("casting to %s (player: %s)" % (args.name or args.host, player["state"]))

        def media(entry):
            player["state"] = entry.get("playerState", player["state"])
            status.set(player=player["state"], idle_reason=entry.get("idleReason", ""))
            if player["state"] == "IDLE" and entry.get("idleReason") in ("ERROR", "FINISHED", "CANCELLED", "INTERRUPTED"):
                if not stop.done():
                    stop.set_result("the device stopped playing (%s)" % entry.get("idleReason"))
        cast.on_media_status = media

        waits = {asyncio.ensure_future(cast.closed.wait()): "the device closed the connection", proc_exit: "the encoder exited",
                 asyncio.ensure_future(asyncio.shield(stop)): None}
        done, _ = await asyncio.wait(set(waits), return_when=asyncio.FIRST_COMPLETED)
        reason = stop.result() if stop.done() else waits[next(iter(done))]
        status.set(state="ended", reason=reason)
        log("ended: %s" % reason)
        return 0
    except (castv2.CastError, RuntimeError, OSError, Exception) as e:  # noqa: BLE001
        log("failed: %s" % e)
        status.set(state="error", error=str(e))
        return 1
    finally:
        if cast:
            if app:
                await cast.stop_app(app)
            await cast.close()
        if proc and proc.returncode is None:
            proc.terminate()
            try:
                await asyncio.wait_for(proc.wait(), 3)
            except asyncio.TimeoutError:
                proc.kill()
        if server:
            await server.stop()
        if capture:
            await capture.close()
        if not args.keep_files:
            shutil.rmtree(workdir, ignore_errors=True)


def build_parser():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--host", required=True, help="the Cast device's address")
    p.add_argument("--port", type=int, default=8009)
    p.add_argument("--name", default="", help="friendly name (for status/logs only)")
    p.add_argument("--source", choices=["portal", "test"], default="portal")
    p.add_argument("--resolution", choices=sorted(RESOLUTIONS), default="1080p")
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--bitrate", type=int, default=8000, help="video kbit/s")
    p.add_argument("--vbv-ms", type=int, default=300, help="x264 rate-control buffer (ms)")
    p.add_argument("--preset", default="veryfast", help="x264 speed preset")
    p.add_argument("--segment-seconds", type=float, default=1.0, help="HLS segment length; shorter = less delay")
    p.add_argument("--no-audio", action="store_true")
    p.add_argument("--audio-source", choices=["system", "tone", "silence"], default="system")
    p.add_argument("--pattern", default="smpte", help="videotestsrc pattern for --source test")
    p.add_argument("--http-port", type=int, default=8765, help="port of the HLS server (open it in the firewall)")
    p.add_argument("--advertise-ip", default=None, help="address to put in the stream URL (default: the one facing the device)")
    p.add_argument("--any-client", action="store_true", help="serve the stream to any LAN host, not only the device")
    p.add_argument("--app-id", default=castv2.DEFAULT_MEDIA_RECEIVER)
    p.add_argument("--ready-timeout", type=int, default=30)
    p.add_argument("--keep-files", action="store_true", help="keep the HLS directory (debugging)")
    p.add_argument("--status-file", default=os.path.join(runtime, "gcast-source.json"))
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    status = Status(args.status_file)
    return asyncio.run(run(args, status))


if __name__ == "__main__":
    sys.exit(main())

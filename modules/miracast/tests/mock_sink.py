#!/usr/bin/env python3
"""A fake Miracast TV for testing the source engine without hardware.

Connects to the engine's RTSP port the way a real sink does, answers M1/M3/M4/M5,
then sends its own M2, M6 (SETUP) and M7 (PLAY), listens on its RTP port, and
reports what it saw as a JSON object on stdout.

  python3 mock_sink.py --host 127.0.0.1 --port 7236 --rtp-port 19000 --listen-seconds 3
"""
import argparse
import asyncio
import json
import os
import socket
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "engine"))
import wfd  # noqa: E402

CAPS = {
    "wfd_content_protection": "none",
    "wfd_video_formats": "38 00 02 08 0001FFFF 1CFFFFFF 00000FFF 00 0000 0000 00 none none",
    "wfd_audio_codecs": "LPCM 00000003 00, AAC 00000001 00",
    "wfd_client_rtp_ports": "RTP/AVP/UDP;unicast %d 0 mode=play",
}


async def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=7236)
    p.add_argument("--rtp-port", type=int, default=19000)
    p.add_argument("--listen-seconds", type=float, default=3.0)
    p.add_argument("--video-formats", default=None)
    args = p.parse_args()

    caps = dict(CAPS)
    caps["wfd_client_rtp_ports"] = caps["wfd_client_rtp_ports"] % args.rtp_port
    if args.video_formats:
        caps["wfd_video_formats"] = args.video_formats

    report = {"m4": None, "setup_reply": None, "play_status": None, "udp_packets": 0,
              "first_payload_sync": None, "errors": []}

    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind(("0.0.0.0", args.rtp_port))
    udp.setblocking(False)

    reader, writer = await asyncio.open_connection(args.host, args.port)
    pending = {}
    cseq = [0]
    m5_seen = asyncio.Event()

    async def req(method, uri, headers=None, body=""):
        cseq[0] += 1
        fut = asyncio.get_running_loop().create_future()
        pending[cseq[0]] = fut
        writer.write(wfd.build_request(method, uri, cseq[0], headers, body))
        await writer.drain()
        return await asyncio.wait_for(fut, 5)

    async def read_loop():
        buf = b""
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                return
            buf += chunk
            while True:
                n = wfd.message_length(buf)
                if n is None:
                    break
                raw, buf = buf[:n], buf[n:]
                m = wfd.parse_message(raw.decode())
                if m.is_response:
                    f = pending.get(m.cseq)
                    if f and not f.done():
                        f.set_result(m)
                    continue
                if m.method == "OPTIONS":                                   # M1
                    writer.write(wfd.build_response(m.cseq, headers={
                        "Public": "org.wfa.wfd1.0, SETUP, TEARDOWN, PLAY, PAUSE, GET_PARAMETER, SET_PARAMETER"}))
                    asyncio.ensure_future(req("OPTIONS", "*", {"Require": "org.wfa.wfd1.0"}))   # M2
                elif m.method == "GET_PARAMETER":                           # M3
                    asked = [x.strip() for x in m.body.split("\n") if x.strip()]
                    body = "".join("%s: %s\r\n" % (k, caps[k]) for k in asked if k in caps)
                    writer.write(wfd.build_response(m.cseq, headers={"Content-Type": "text/parameters"}, body=body))
                elif m.method == "SET_PARAMETER":
                    params = wfd.parse_params(m.body)
                    if "wfd_trigger_method" in params:                      # M5
                        writer.write(wfd.build_response(m.cseq))
                        m5_seen.set()
                    else:                                                   # M4
                        report["m4"] = params
                        writer.write(wfd.build_response(m.cseq))
                await writer.drain()

    task = asyncio.ensure_future(read_loop())
    try:
        await asyncio.wait_for(m5_seen.wait(), 8)
        r = await req("SETUP", "rtsp://%s/wfd1.0/streamid=0" % args.host,
                      {"Transport": "RTP/AVP/UDP;unicast;client_port=%d" % args.rtp_port})   # M6
        report["setup_reply"] = {"status": r.status, "transport": r.headers.get("transport"),
                                 "session": r.headers.get("session")}
        r = await req("PLAY", "rtsp://%s/wfd1.0/streamid=0" % args.host,
                      {"Session": r.headers.get("session", "").split(";")[0]})              # M7
        report["play_status"] = r.status
        loop = asyncio.get_running_loop()
        end = loop.time() + args.listen_seconds
        while loop.time() < end:
            try:
                data = udp.recv(4096)
            except BlockingIOError:
                await asyncio.sleep(0.05)
                continue
            report["udp_packets"] += 1
            if report["first_payload_sync"] is None and len(data) > 12:
                report["first_payload_sync"] = data[12] == 0x47        # RTP header is 12 bytes
        r = await req("TEARDOWN", "rtsp://%s/wfd1.0/streamid=0" % args.host)
    except Exception as e:  # noqa: BLE001
        report["errors"].append(repr(e))
    task.cancel()
    writer.close()
    print(json.dumps(report))


if __name__ == "__main__":
    asyncio.run(main())

# Google Cast (modules/gcast)

Cast the screen to Chromecasts, Google TVs / Android TVs with Cast built in, Nest speakers and displays, and
Cast-enabled TVs: `coel-gcast`.

```
coel-gcast scan                                  # what is on the network (mDNS _googlecast._tcp)
coel-gcast cast "Living Room"                    # pick what to share, then it plays on the device
coel-gcast cast 192.168.0.50 --resolution 720p   # by address; extra flags go to the engine
coel-gcast status | stop | logs
```

NixOS: `services.gcast.enable = true;` (needs `services.avahi.enable`). Options: `httpPort` (8765), `openFirewall` (true).

## Status: written and tested against a mock device only

**Nothing here has run against a real Cast device yet.** What is verified: the protocol client against a protocol-level
mock (and its protobuf against Google's own `protoc --decode_raw`), the HLS stream (valid live playlist, MPEG-TS
segments with H.264 High 4.1 + AAC, CORS), the engine end to end against the mock, and the packaged (Nix-built)
engine in a clean environment. What is *not* verified is how a real Default Media Receiver reacts. See "Risks".

## How it works (and why it is not Chrome's mirroring)

Chrome mirrors with the *Cast Streaming* protocol (an encrypted RTP session negotiated through a Chrome-only receiver
app): low latency, but a large, Google-controlled protocol. This module uses the route every Cast device supports:

1. Capture the screen (xdg-desktop-portal, shared with the Miracast module: `modules/castlib/portal_capture.py`) and
   system audio, encode H.264 High 4.1 + AAC-LC into a live **HLS** stream (`hlssink2`: `live.m3u8` plus 1 s
   MPEG-TS segments) in a private directory.
2. Serve it over HTTP (`engine/hls.py`). Cast receivers are web pages that fetch the media themselves, so the server
   sends `Access-Control-Allow-Origin: *`, the URL has a random token, and only the device's IP may fetch it.
3. Speak CASTV2 (`engine/castv2.py`, stdlib only): TLS to port 8009, protobuf `CastMessage` frames, `CONNECT`, a 5 s
   heartbeat, `LAUNCH` the Default Media Receiver (`CC1AD845`), `CONNECT` to its `transportId`, then `LOAD` the URL with
   `contentType application/x-mpegURL`, `streamType LIVE`. `MEDIA_STATUS` is watched: if the device goes `IDLE`
   (error/finished) the cast ends. On stop the app is stopped on the device.

**Cost: latency.** HLS players buffer a few segments: expect 3-6 s. Fine for video, slides and music; not for
games or typing. `--segment-seconds` trades delay against robustness.

## Layout

```
modules/castlib/portal_capture.py   screen capture via the portal (shared with miracast)
modules/gcast/
  default.nix            services.gcast, coel-gcast wrapper, firewall port
  engine/castv2.py       CASTV2 client (protobuf codec, TLS, heartbeat, launch/load/stop)
  engine/discover.py     avahi browse + parsing of _googlecast._tcp, device lookup by name/model/id/address
  engine/hls.py          HLS HTTP server (CORS, token, device-only) + readiness check
  engine/gcast_engine.py capture -> hlssink2 -> serve -> connect -> LOAD -> watch -> stop; JSON status file
  ctl/gcast_ctl.py       coel-gcast
  tests/mock_cast.py     a fake Cast device (TLS, CASTV2, fetches the stream like a receiver)
  tests/integration.py   engine <-> mock end to end
  engine/test_*.py       codec/client, discovery, HLS server
```

Status file: `$XDG_RUNTIME_DIR/gcast-source.json` (`state`: starting / choosing / preparing / connecting / loading /
casting / ended / error, plus `device`, `url`, `player`, `error`/`reason`) for a future Quickshell front end, the same
shape idea as the Miracast engine's.

## Testing without a device

```
cd modules/gcast
python3 -m unittest discover -s engine -p 'test_*.py'      # protocol, discovery, HLS server (needs openssl)
PATH=<gstreamer>/bin GST_PLUGIN_SYSTEM_PATH_1_0=... python3 -m unittest tests/integration.py
python3 tests/mock_cast.py --port 18009 &                  # a mock device you can point coel-gcast at:
coel-gcast cast 127.0.0.1:18009 --source test --foreground
```

The mock checks what a real receiver needs from the stream (playlist is live HLS, CORS header, first segment is
MPEG-TS) and answers `LOAD_FAILED` with the reason otherwise. It cannot tell us whether a real device *decodes* it.

Ways to get a real receiver for a test (none tried): an Android TV / Google TV box or any TV with "Chromecast built-in"
(Sony, TCL, Hisense, Philips, Vizio...), a Chromecast dongle, a Nest Hub/Mini (audio only: use `--audio-only` once it
exists), or the Android Studio *Android TV* emulator with a Google APIs image (it advertises Cast but needs bridged
networking). Fire TV and Roku are **not** Cast receivers.

## Risks (things only a real device can settle)

- **Does the Default Media Receiver accept `hlssink2`'s segments?** Google documents HLS with MPEG-TS segments and
  H.264 High up to level 4.1 (1080p30); `hlssink2` produces exactly that. The first segment's PAT/PMT must list both
  streams (the Roku lesson, see modules/miracast/README.md): they come from one muxer started together, but unverified.
- **CORS**: sent on every response (including errors); the one documented requirement.
- **Network**: guest/campus Wi-Fi isolates clients and drops mDNS (no discovery) and device-to-laptop traffic (the
  device cannot fetch the stream). Same subnet, no AP isolation. The HLS port must be open (`openFirewall`).
- **IPv6 only / several addresses**: the stream URL uses the IPv4 address facing the device; override with `--advertise-ip`.
- **Device authentication** (`tp.deviceauth`) is not used; third-party senders (pychromecast, VLC) work without it.
- **Wired vs Wi-Fi** doesn't matter, but the laptop must not be on a VPN that hijacks the LAN route (the GlobalProtect
  note in the memory file applies: casting to a LAN device while connected will fail).

## Possible next steps

Audio-only mode for speakers (`--audio-only`: no video, `audio/aac` HLS or `audio/mpeg`), a profile system like the
Miracast one (match by model `md`/capabilities `ca`: resolution/fps per device generation), Cast Streaming
(low-latency mirroring) if the delay turns out to matter, and a Quickshell front end over both engines' status files.

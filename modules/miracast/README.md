# Miracast on CoelOS

Cast this laptop's screen to a Miracast sink (Fire TV Stick, Roku, smart TVs), declared
in NixOS, built from layers that talk through small interfaces (a JSON state file and a
JSON-lines socket) so the discovery back end, engine or front end can be replaced alone.
Google Cast is a separate module (`modules/gcast`), sharing only `../castlib/portal_capture.py`.

Rules: everything installs through the NixOS module in `default.nix` (no hand-made files);
no dependence on NetworkManager's Wi-Fi P2P (see below).

## State

| Display | Link | Stream | Status |
|---|---|---|---|
| Fire TV Stick | Wi-Fi Direct GO negotiation, we are client (`192.168.49.x`) | 1080p30 H.264 + AAC | Works, a bit choppy. Audio-timestamp fix and PMT/relay rework not re-tested on it |
| Roku Express 898 | We *join* its existing group (it is already a GO); `172.29.243.x` | 1080p30 High 4.1 + AAC | Screen + audio worked; later smoothing change not re-tested |

No Quickshell modal exists yet; `state.json` and the socket are its interface.

## Layers

```
 front ends: coel-miracast CLI (done), Quickshell modal (todo), any script
        |  state.json (read)      linkd.sock (JSON lines)
 miracast-linkd (root, hardened)   linkd/      wpa_supplicant D-Bus: scan, peers, WFD IE, P2P connect, DHCP unit
        |  link ready: p2p-wlp1s0-N has an IP
 source engine (user, one per cast) engine/    RTSP :7236, WFD negotiation, PipeWire capture, x264, MPEG-TS/RTP
```

### `/run/miracast/state.json`
World-readable, atomically replaced, written at most once a second. Keys: `wpa`
(up/down), `interface`, `scanning`, `scan_remaining`, `link` (`state`:
idle|connecting|linked|ready|error, plus `role`, `interface`, `local_ip`, `remote_ip`,
`rtsp_port`), `error`, `peers[]` (`address`, `name`, `model`, `rssi`, `is_sink`, `wfd{role,
session_available, content_protection, port}`, `age`).

### `/run/miracast/linkd.sock`
Group-writable (`services.miracast.group`, default `users`). One JSON object per line:
`status`, `scan {on, seconds}`, `connect {address, go_intent, join}`, `disconnect`, `flush`.
Replies `{"ok":true,...}` / `{"ok":false,"error":"..."}`.

### Engine status
`$XDG_RUNTIME_DIR/miracast-source.json`: listening|negotiating|ready|setup|streaming|ended|error.
It only accepts the sink the link is up with (`link.remote_ip`).

## How a cast works

1. `coel-miracast cast "<name>" --source portal` starts `miracast-source` as a transient
   user unit. For `portal` it asks xdg-desktop-portal (our Quickshell share picker) what
   to share *first* (the sink gives up within seconds, the picker waits for a human).
2. linkd scans, forms the group (GO negotiation, or `join` if the peer's group capability
   has the GO bit), runs `udhcpc` via `miracast-dhcp@<if>.service`, publishes `ready`.
   Group formation is intermittent, so connect retries 3x, rescanning first.
3. The sink connects to our RTSP port. Engine: M1, wait for the sink's own M2 (Roku requires
   it before M3), M3, profile match, M4 (one video mode; AAC if offered; HDCP advertised
   -> `wfd_content_protection: none`), M5 trigger, then SETUP/PLAY. M16 keep-alive every 25 s.
4. Video: `pipewiresrc provide-clock=false` -> `videoconvert` -> `capssetter` (fixes xdph's
   bogus pixel-aspect-ratio) -> leaky queue -> `videoscale` lanczos + borders -> `videorate`
   -> `x264enc` (veryfast, 12 Mbit/s, GOP 30, no B-frames, `vbv-buf-capacity=30`, BT.709)
   -> `h264parse config-interval=-1` -> `mpegtsmux`.
5. Audio: a separate capture process (speaker monitor, `node.latency=1024/48000`, AAC-LC),
   started `--audio-start-delay-ms` (1000) after video. The engine relays one AAC frame per
   UDP datagram, ADTS header rewritten to MPEG-2 (`FF F9`, as AOSP), into
   `udpsrc caps=audio/mpeg,...adts,framed=true ! queue ! mux.sink_4352`.
6. Mux follows the WFD spec as far as `mpegtsmux` allows: video PID 0x1011, audio 0x1100,
   PMT PID 0x100, PAT/PMT every 50 ms, PCR on video. Then `rtpmp2tpay` -> `udpsink`.

## Commands

```sh
coel-miracast scan 30                  # the sink must be on its mirroring screen
coel-miracast peers --all
coel-miracast cast "Joel's Fire TV" --source portal      # screen + system audio
coel-miracast cast "Roku" --source test --pattern smpte  # colour bars, no picker
coel-miracast stop; coel-miracast disconnect             # between attempts, always both
coel-miracast engine; coel-miracast logs; coel-miracast scan-stop
```

`cast` forwards engine flags: `--bitrate`, `--vbv-ms`, `--preference 5` (720p30), `--preset`,
`--color bt709|bt709-full|bt601`, `--contrast/--saturation/--gamma`, `--audio-source
system|silence|tone|monitor|off`, `--audio-preference AAC,LPCM`, `--audio-start-delay-ms`,
`--profiles FILE`, `--encoder va` (experimental), `--no-ts-spec`, `--aac-mpeg4-adts`,
`--mux-bitrate`, `--strict-levels`. Diagnostics: `--source testcap` (synthetic 2256x1504
screen through the exact portal chain), `--chain-skip`, `--cap-format`, `--cap-size`.
`--no-audio` stops the Roku answering M4: don't use it there.

`services.miracast.*`: `enable`, `interface`, `group`, `deviceName`, `scanSeconds`, `peerTtl`,
`rtspPort`, `sinkProfiles`, `keepStationAutoconnect`, `unmanageP2pInNetworkManager`,
`protectWpaSupplicantFromP2pInterfaces`, `openFirewall` (off: the 7236 rule is in `configuration.nix`).

## Per-display profiles

Capabilities come from M3; quirks that can't be discovered live in `engine/profiles.py`
profiles (`services.miracast.sinkProfiles.<name> = { match = {name = "regex";}; settings =
{bitrate = 8000;}; }`). Match fields: `name`, `manufacturer`, `model`, `device_type`,
`content_protection`, `audio_codecs`. Yours first, then built-ins (`roku`, `fire-tv`, currently
no overrides), first match wins; command-line flags beat profiles. LPCM is experimental
(mpegtsmux writes stream_type 0x8b, AOSP uses 0x83 + a PMT descriptor); never tried on real hardware.

## Rules learned the hard way

- **The Roku reads the first PMT once and only plays streams listed in it.** `mpegtsmux`
  lists a stream only after its pad has caps, so whichever stream produced data first was
  alone in the PMT (audio first -> black screen; video first -> no sound). Hence the audio
  branch declares caps up front. Verify with `tests/miracast/mock_sink.py --dump f.ts`.
- The Roku stops answering when told there is no audio; negotiate AAC and send silence.
- **Never call `P2PDevice.Disconnect` on the main interface**: wpa_supplicant treats it as
  "deauthenticate this interface" and drops normal Wi-Fi. End a group on its own `p2p-*`
  interface; linkd ends every group interface on `disconnect` and before each connect (a
  stale one fails the next group with "Device or resource busy"; manual cleanup:
  `sudo iw dev p2p-wlp1s0-N del`).
- NixOS's `networking.wireless` installs a udev rule restarting wpa_supplicant on every
  wlan add/remove, which kills the P2P group. `protectWpaSupplicantFromP2pInterfaces` sets
  `networking.wireless.interfaces` to remove it (wpa then runs as `wpa_supplicant-wlp1s0`).
- NetworkManager stops autoconnecting after 4 failures; `keepStationAutoconnect` raises
  `autoconnect-retries-default`. A rebuild changing NM config briefly drops Wi-Fi.
- Don't force the P2P channel to the station's (`--match-station-channel`, opt-in): the
  Fire TV then ignored GO negotiation. The mt7921 does two-channel concurrency anyway.
- Audio timestamps must be smooth: needs the `queue` after `udpsrc` (mpegtsmux holds its
  audio pad while waiting for video, which makes udpsrc stamp bursts with one time) and
  one-frame capture buffers. Ideal PTS step 21.3 ms.
- `pipewiresrc` must not provide the clock (stalls on a static screen -> black TV).
  `videoconvert` must precede `capssetter` or negotiation fails ("target not found").
- Keep keyframes small (`vbv-buf-capacity=30`): a static desktop IDR is ~180 KB otherwise.
- The first stream died at exactly 3 minutes because `--idle-timeout` covered the whole
  run; it only covers the wait for a sink now. `cast` must delete the previous run's
  status file or it reads the old error and kills the fresh engine.
- Between attempts: `stop` and `disconnect`, reopen the sink's mirroring screen. A sink left
  waiting for minutes or after many failures can stop replying (frames ack'd, no reply):
  power-cycle it. Roku: Settings > System > Screen mirroring, "Prompt" or "Always allow".
- Fire TV advertises only Constrained Baseline and 1080p30 at level 3.1 but decodes 4.0:
  the engine trusts the advertised mode. The TV ignores range/matrix tags and always decodes
  BT.709 limited, so default colour is correct; use `--contrast/--saturation/--gamma` to taste.

## Why not NetworkManager

NM's Wi-Fi P2P API showed an empty peer list even though wpa_supplicant found the TVs
(wpa emits `DeviceFound`; NM never requests the peer object; cause unknown, restarts don't
help). So linkd talks to wpa_supplicant's root-only D-Bus API directly. Facts that shaped it:
the `p2p-dev-*` interface isn't on D-Bus, P2P API and `Peers/<mac>` live under the main
interface; a peer object is only published the first time it's found, so linkd seeds from
`Peers` on attach and re-attaches when the interface is re-created; scanning briefly
disturbs the normal link, so keep scans short and on demand. A sink only appears while on
its mirroring screen (not in mDNS), and scanning can take 10-30 s.

## Known issues / open

- Re-test both sinks after the audio timing/relay changes (Fire TV first).
- Lip-sync: audio is stamped on reaching the muxer, so it can trail video 20-60 ms;
  `mpegtsmux` has no per-stream offset. Fix would be carrying capture timestamps over RTP.
- Latency a few hundred ms to ~1 s, mostly the sink's buffer plus our 125-165 ms PTS-to-PCR lead.
- `--encoder va` is ~2x faster but produced flat images from PipeWire sources; off.
- No HDCP, no honouring `wfd_idr_request` (periodic IDR <= 1 s heals losses), software encode default.
- The 7236 firewall rule in `configuration.nix` isn't scoped to `p2p-*`.
- Roku-specific protocol docs don't exist publicly; AOSP's `TSPacketizer.cpp` and
  gnome-network-displays (`wfd-media-factory.c`) are the references.

Disproved explanations (don't repeat): audio-first start order (an ffprobe stream-index
mix-up), oversized keyframes blacking the Roku, "static screen = too little data"
(`--mux-bitrate` stays as an option), `clocksync` audio delay, forcing the P2P channel,
"scanning drops the Wi-Fi" (it was our own Disconnect call). The MPEG-2 ADTS header went in
together with the PMT fix, so whether the Roku needs it is unknown.

## Debugging

```sh
systemctl status miracast-linkd; journalctl -u miracast-linkd -b; coel-miracast status
journalctl -b -u wpa_supplicant-wlp1s0 | grep P2P-
sudo busctl set-property fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 DebugLevel s debug   # set back to info after
sudo busctl --system monitor --verbose fi.w1.wpa_supplicant1
```

## Tests (no hardware, root or TV needed)

`python3 tests/run.py miracast` runs everything: unit (`miracast-wfd/profiles/linkd`),
`miracast-engine-e2e` (engine vs mock TV), `miracast-integration` (daemon + CLI vs
`mock_wpa.py`, which asserts Disconnect never reaches the main interface),
`miracast-portal`. `bash tests/miracast/engine_e2e.sh gst` also streams a test pattern.
`tests/miracast/mock_sink.py --dump f.ts` is a fake TV that writes the received MPEG-TS
(check PIDs, PMT, timestamp steps). The portal picker can't be automated.

## Files

```
modules/miracast/
  default.nix               NixOS module (link daemon, DHCP template unit, CLI, profiles, NM settings)
  linkd/miracast_linkd.py   root daemon
  engine/miracast_source.py RTSP session, profile match, pipelines, audio relay
  engine/wfd.py             WFD protocol logic (pure, unit tested)
  engine/profiles.py        per-display quirk profiles
  ctl/miracast_ctl.py       coel-miracast CLI (stdlib only)
../castlib/portal_capture.py  ScreenCast portal client (shared with ../gcast)
tests: ../../tests/miracast/
```

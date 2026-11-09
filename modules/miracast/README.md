# Miracast on CoelOS

Casting this laptop's screen to a Miracast sink (Amazon Fire TV Stick, smart
TVs) from a Quickshell modal, declared in NixOS, built from separate pieces so
no single front end or back end is baked in.

Written 2026-11-06/07 after a long debugging session. This file is the
reference for what we learned, how the pieces fit, and what is left.

## Ground rules

1. **Declarative.** Everything installs and configures through the NixOS module
   in `default.nix`. No hand-made files, no imperative setup.
2. **Organized.** One directory, one README, tests next to the code.
3. **Modular.** Each layer talks to the next through a small, documented
   interface (a JSON state file and a JSON-lines socket). Replace the engine,
   the discovery back end, or the front end without touching the others.
4. **No dependency on NetworkManager's Wi-Fi P2P** (see "Why not NetworkManager").

## Status

| Phase | What | State |
|---|---|---|
| 1 | Discovery: find Miracast sinks, publish them | **Working on the real radio** |
| 2 | Link: Wi-Fi Direct group with the TV, IP on the group interface | **Working** with the Fire TV: group forms, DHCP lease (`192.168.49.x`), link `ready` |
| 3 | Source engine: WFD RTSP negotiation, capture, encode, stream | **Working on the Fire TV** with a test pattern (2026-11-06, 720p30). Screen capture through the portal is written and tested against a mock portal; **not yet run on the real desktop** |
| 4 | Front ends: CLI (done), Quickshell modal, keybinds | CLI done (`coel-miracast cast`); modal not started |

## What we learned

### The hardware is fine, the TVs are visible

- The Wi-Fi chip (MediaTek mt7921e) supports P2P client/GO/device and can keep
  the normal connection while doing Wi-Fi Direct (`iw phy`: managed + P2P-device,
  up to 2 channels).
- `wpa_supplicant` 2.12 finds both `Joel's Fire TV` and `bedroom tv`, with their
  Wi-Fi Display capabilities (`wfd_dev_info`), and the phone finds them too.
- A Fire TV only appears when it is sitting on *Settings > Display & Sounds >
  Enable Display Mirroring*. It never shows up in an mDNS/LAN scan: Miracast is
  not an IP-network protocol at discovery time.

### Why not NetworkManager

gnome-network-displays (and anything built on NetworkManager's Wi-Fi P2P API)
showed an empty list even though `wpa_supplicant` had the TVs. Evidence, from a
`busctl monitor` capture of wpa_supplicant's D-Bus traffic and NetworkManager
1.56.0's source:

- NetworkManager starts the scan (`StartFind` → `P2PDevice.Find`) and reads the
  interface's P2P properties at startup. All fine.
- wpa_supplicant then emits `DeviceFound` and `DeviceFoundProperties` for the
  Fire TV on the right interface, with complete data.
- NetworkManager never sends the follow-up request for the peer object, never
  logs anything about it (even with TRACE logging), and its `Peers` property
  stays empty.
- The NetworkManager source has no step that should drop it. Cause unknown.
  Restarting NetworkManager, restarting wpa_supplicant, and restarting both did
  not change it.

So the way around it is to not use NetworkManager for P2P at all: talk to
wpa_supplicant directly. That needs root (its D-Bus API is root-only), hence the
small privileged daemon below.

### wpa_supplicant facts that shaped the design

- The `p2p-dev-*` interface is never published on D-Bus by design
  (`wpas_notify_iface_added` skips `p2p_mgmt` interfaces). The P2P API and the
  peer objects live under the **main** interface (`Interfaces/N`, and
  `Interfaces/N/Peers/<mac>`).
- A peer's D-Bus object is only created the first time it is found
  (`new=1`). A long-running daemon that already knows a peer will not re-publish
  it, so a client that missed the first announcement sees nothing until
  `Flush`. The daemon therefore seeds from the `Peers` property on attach and
  re-attaches whenever the interface is re-created (NetworkManager does that).
- `DeviceFoundProperties` carries everything (name, address, WFD IEs), so a
  single signal handler is enough; no per-peer round trips.
- While scanning, the normal connection briefly drops to `authenticating`
  (seen in the capture). Scans should be short and on demand, never continuous.

### Connecting dropped the normal Wi-Fi (found 2026-11-06)

Running `coel-miracast connect` disconnected the laptop from its Wi-Fi and the
link never formed. The journal showed `wpa_supplicant.service` being stopped and
started **twice in the same second** on every attempt, which looked like a crash
but was a clean systemd restart.

Cause: NixOS's `networking.wireless` module (which NetworkManager turns on)
installs a udev rule in `99-local.rules`:

```
ACTION=="add|remove", SUBSYSTEM=="net", ENV{DEVTYPE}=="wlan",
RUN+="systemctl try-restart wpa_supplicant.service"
```

A Wi-Fi Direct link makes wpa_supplicant create a `p2p-wlp1s0-0` network
interface, which is `DEVTYPE=wlan`: **add** restarts wpa_supplicant (killing the
group it just created and the station link), and the interface's **removal**
restarts it again. The rule only exists while `networking.wireless.interfaces`
is empty (`nixos/modules/services/networking/wpa_supplicant.nix`).

Fix: `services.miracast.protectWpaSupplicantFromP2pInterfaces` (default on)
sets `networking.wireless.interfaces = [ services.miracast.interface ]`, which
removes the rule. wpa_supplicant then runs as `wpa_supplicant-wlp1s0.service`
with the same arguments plus `-iwlp1s0`. Other ways we tried and ruled out
(current udev rejects them): `OPTIONS+="last_rule"`, `RUN-=`, and setting
`ENV{DEVTYPE}`.

### First successful link (2026-11-06)

With the three fixes above (no wpa_supplicant restarts, scan timer no longer
cancels the connection, `p2p-*` unmanaged in NetworkManager) the Fire TV accepted
the connection:

```
P2P-GROUP-STARTED p2p-wlp1s0-2 client ssid="DIRECT-iX-FireTV_5bed" freq=5240
                  go_dev_addr=6a:9a:87:3c:4e:b4 [PERSISTENT]
```

- We were the **client**, the TV the **group owner** (we asked for GO intent 0),
  on channel 48 (5240 MHz) while the normal Wi-Fi stayed up on 5745 MHz: the
  chip really does run both at once.
- The WPA2 handshake completed and the TV showed its "loading" screen.
- 50 seconds later the TV ended the session (`GO_ENDING_SESSION`) and left
  Display Mirroring, because nothing came next: no IP address had been set up on
  the group interface and nothing was listening on the RTSP port. That is
  exactly what phases 2b and 3 supply.
- The first GO Negotiation Request is often not acknowledged (the TV is not
  listening on that channel at that instant); wpa_supplicant retries, so connect
  needs a few seconds.
- No IP-address-allocation fields in `P2P-GROUP-STARTED`, so the TV runs a DHCP
  server: we use a DHCP client on the group interface.

Group formation is **intermittent** (2026-11-06): one attempt got the TV's
`GO Negotiation rejected: status 1` ("not ready", it then initiated the
negotiation itself and `P2P-GO-NEG-SUCCESS` followed), WPS succeeded
(`P2P-GROUP-FORMATION-SUCCESS`), and then the rejoin with the new credentials
died with `EAP authentication failed` and `P2P-GROUP-FORMATION-FAILURE`. Other
attempts on the same hardware went straight through. `miracast-linkd` therefore
retries (3 attempts, `--connect-retries`) on `GroupFormationFailure` /
`GONegotiationFailure`, rescanning first because a failed group drops the peer.
A TV that ends a session also leaves Display Mirroring: put it back on that
screen before the next attempt.

Link states in `state.json`: `connecting` (negotiating), `linked` (group up, no
address yet), `ready` (has an IP: `local_ip`, `remote_ip` = the TV, `rtsp_port`),
`error` (with `reason`), `idle`.

### Fire TV details

- Primary device type reported as `10-0050F204-5`; WFD IE
  `00 0006 0011 1c44 0032` = device info `0x0011` (primary **sink**, session
  available), RTSP port **7236**, max throughput 50. Content protection off.
- `bedroom tv`: `0x0111` (sink, available, **content protection** supported).
- The TV is the RTSP *client's* peer, not a server: after the Wi-Fi Direct link
  is up **the sink connects to the source's port 7236**. That is why 7236 is
  open in `configuration.nix`.

## Architecture

```
  front ends (any number, none required)
  ┌──────────────┐  ┌───────────────────┐  ┌───────────────┐
  │ coel-miracast│  │ Quickshell modal  │  │ keybind / any │
  │   (CLI) done │  │   (phase 4)       │  │ script        │
  └──────┬───────┘  └─────────┬─────────┘  └───────┬───────┘
         └────────────────────┼────────────────────┘
                              │  state.json (read)   linkd.sock (JSON lines)
  ┌───────────────────────────▼────────────────────────────────┐
  │ miracast-linkd (root)  phases 1-2      linkd/                │
  │  wpa_supplicant D-Bus: scan, peers, WFD IE, P2P connect      │
  └───────────────────────────┬────────────────────────────────┘
                              │  link up: p2p-wlp1s0-N has an IP
  ┌───────────────────────────▼────────────────────────────────┐
  │ source engine (user)   phase 3        (not written yet)      │
  │  RTSP server :7236, WFD negotiation, PipeWire capture,       │
  │  H.264 encode, MPEG-TS over RTP to the TV                    │
  └────────────────────────────────────────────────────────────┘
```

Layers only know the interface below them. In particular:

- A different discovery back end (say, NetworkManager if it gets fixed) only has
  to write the same `state.json`.
- A different engine only needs the link's interface name and the peer's
  address, both in `state.json`.
- The Quickshell modal is a plain reader of `state.json` plus a writer to the
  socket; it needs no D-Bus and no root.

## Interfaces

### `/run/miracast/state.json`

World-readable, replaced atomically (watch the directory or poll), rewritten at
most once a second.

```json
{
  "version": 1,
  "updated": 1794019467.2,
  "wpa": "up",                  // up | down
  "interface": "wlp1s0",
  "scanning": true,
  "scan_remaining": 41,
  "link": { "state": "idle" },  // idle | connecting | connected | error
  "error": "",
  "peers": [
    {
      "address": "6a:9a:87:3c:4e:b4",
      "name": "Joel's Fire TV",
      "manufacturer": "", "model": "UB134_STATION",
      "device_type": "10-0050F204-5",
      "rssi": -60,
      "wfd": { "present": true, "role": "sink", "is_sink": true,
               "session_available": true, "content_protection": false,
               "port": 7236, "max_throughput": 50 },
      "is_sink": true,
      "last_seen": 1794019465.1, "age": 2.1
    }
  ]
}
```

When connected, `link` becomes
`{"state":"connected","role":"client","interface":"p2p-wlp1s0-0","group":"/…"}`.

### `/run/miracast/linkd.sock`

Group-writable (`services.miracast.group`, default `users`). One JSON object per
line in, one per line out.

| Request | Effect |
|---|---|
| `{"cmd":"status"}` | returns the same object as state.json |
| `{"cmd":"scan","on":true,"seconds":60}` | start scanning; auto-stops |
| `{"cmd":"scan","on":false}` | stop scanning |
| `{"cmd":"connect","address":"6a:9a:…","go_intent":0}` | form a P2P group (WPS push-button) |
| `{"cmd":"disconnect"}` | tear the group down |
| `{"cmd":"flush"}` | forget all peers |

Replies: `{"ok":true,…}` or `{"ok":false,"error":"…"}`.

## NixOS module (`default.nix`)

`services.miracast.enable = true;` with `interface = "wlp1s0"` (already imported
and set in `configuration.nix`). Options: `interface` (null = auto), `group`, `deviceName`
(defaults to the hostname), `scanSeconds`, `peerTtl`, `rtspPort`,
`unmanageP2pInNetworkManager` (default true; marks `p2p-*` unmanaged so NM does
not run its own competing scan or touch the group interface),
`protectWpaSupplicantFromP2pInterfaces` (default true; see above, needs
`interface`), `openFirewall`
(default false: this machine's firewall is managed in `configuration.nix`).

It installs `miracast-linkd` as a hardened root systemd service (no
capabilities, `ProtectSystem=strict`, only `AF_UNIX`) and the `coel-miracast`
CLI.

```sh
coel-miracast scan 30      # start looking (Fire TV must be on the Display Mirroring screen)
coel-miracast peers        # table of sinks
coel-miracast watch        # live list
coel-miracast status
coel-miracast json
```

## What is left

### Phase 2: link

Group formation works. **Addressing** is built but not yet run on hardware: on
`GroupStarted` as client, `miracast-linkd` starts the template unit
`miracast-dhcp@<interface>.service` (declared in `default.nix`; busybox `udhcpc`
with a small script, no default route, no DNS) through systemd's D-Bus API, waits
for the lease file `/run/miracast/lease-<interface>.json`, and moves the link to
`ready`. The unit is stopped and the lease removed when the group ends. If a TV
insists on us being the group owner we would need a DHCP *server* instead.

Still to do:
- Firewall: allow `rtspPort` on `p2p-*` only (the current rule in
  `configuration.nix` opens it on every interface; it is also unclear whether
  that NixOS rule or firewalld is the one in effect).
- The connection must be fast: the TV gives up after roughly 50 seconds, so the
  engine has to be ready to accept its RTSP connection right after `ready`.

### Phase 3: source engine

`engine/` (`miracast_source.py` + `wfd.py`), run as the **user** on demand by
`coel-miracast cast` (a transient `systemd-run --user` unit named
`miracast-source`, so its log is `coel-miracast logs`). It listens on TCP 7236,
accepts only the TV the link is up with (checked against `state.json`:
`link.state == ready` and `link.remote_ip` equals the peer; the socket itself
listens on all interfaces), negotiates over RTSP, and runs a `gst-launch-1.0`
child process for the stream. It writes `$XDG_RUNTIME_DIR/miracast-source.json`
(`listening | negotiating | ready | setup | streaming | ended | error`).

WFD source flow (all implemented, in `wfd.py`):

1. The TV connects to us on 7236. We send **M1** `OPTIONS` and answer its
   **M2**.
2. **M3** `GET_PARAMETER`: read its `wfd_video_formats` and RTP port.
3. **M4** `SET_PARAMETER`: choose one mode. We pick the best of 1080p30, 720p30,
   720p60, 1080p60 (CEA table bits 7,5,6,8), the sink's best H.264 level up to
   4.1, constrained baseline if offered else high. Video only (`wfd_audio_codecs:
   none`) for now.
4. **M5** `wfd_trigger_method: SETUP`; the TV sends **M6** `SETUP` (we reply with
   our UDP port 5000) and **M7** `PLAY`; keep-alives are answered; `TEARDOWN`
   ends it.
5. On PLAY: `x264enc` (zerolatency, no B-frames, keyframe every second) `!
   h264parse ! mpegtsmux alignment=7 ! rtpmp2tpay ! udpsink` to the TV's port.

Sources (`--source`): `test` (GStreamer ball pattern: proves the whole chain
without any capture permission; **verified on the Fire TV**), `portal` (screen
through the xdg-desktop-portal screencast into `pipewiresrc`; `portal_capture.py`),
`none` (negotiation only).

The portal source asks what to share **first**, before the engine listens
(`coel-miracast cast ... --source portal` shows the picker, then connects): the
TV gives up within seconds if the stream is slow to start after PLAY, and the
picker waits for a human. The pipeline scales with `videoscale add-borders` to
keep the aspect ratio and uses `keepalive-time` + `videorate` to keep frames flowing while the
screen is idle (the portal only sends frames on change).

Lesson learned (black TV with the portal source): `pipewiresrc` provides the
pipeline clock by default, and that clock stalls when the screen is static, so
the encoder produced ~1 frame per several seconds and the TV showed black.
`provide-clock=false` fixes it (measured: 238 frames in 8 s, decodable).

Lesson learned: the first successful stream stopped after exactly three minutes.
`--idle-timeout 180` (meant for "no TV ever connected") was applied to the whole
run. It now only covers the wait for a TV; `tests/engine_e2e.sh` runs with a
timeout shorter than the session so this can't come back.

Known gaps: no audio (LPCM/AAC in the TS), no HDCP, no forced-keyframe on the
sink's `wfd_idr_request` (a keyframe arrives within a second anyway), software
encoding only, the firewall rule for 7236 is not yet scoped to the P2P interface.

```sh
coel-miracast cast "Joel's Fire TV"      # engine + scan + connect + stream the test pattern
coel-miracast logs                        # engine log
coel-miracast engine                      # engine status json
coel-miracast stop
```

### Phase 4: front ends

The Quickshell modal reads `state.json` (FileView on the directory) and writes
to the socket (a `Process` running `coel-miracast`, or a socket client). It owns
no state of its own. A Google Cast back end can later sit beside this one as a
second source of devices behind the same modal, which is why the modal should
talk to the *interfaces above*, not to the Miracast daemon's internals.

## Risks and open questions

- Phase 1 has only run against a mock. The first real run may show wpa_supplicant
  behaviours the mock does not (e.g. signal paths, `Find` argument handling).
- Scanning briefly disturbs the normal Wi-Fi link (observed). Keep scans short.
- Some TVs insist on being the P2P client, or require WPS PIN rather than
  push-button. Fire TV Display Mirroring is expected to work with push-button.
- Encoder choice: hardware (VA-API on the Radeon 760M) vs `x264enc` for the
  lowest latency. To be benchmarked in phase 3.
- Content-protected sinks (`bedroom tv` advertises it) may refuse unprotected
  streams; we do not plan to implement HDCP.
- The `networking.firewall.allowedTCPPorts = [ 7236 ]` line in
  `configuration.nix` predates this module; it should move behind
  `services.miracast` and be scoped to `p2p-*` in phase 2.

## Debugging cookbook

```sh
# is the daemon up, and what does it see?
systemctl status miracast-linkd
journalctl -u miracast-linkd -b
coel-miracast status; coel-miracast json

# wpa_supplicant's own view (journal is readable without root)
journalctl -b -u wpa_supplicant | grep -E "P2P-DEVICE-FOUND|P2P-"

# raw D-Bus traffic to/from wpa_supplicant (root)
sudo busctl --system monitor --verbose fi.w1.wpa_supplicant1 > /tmp/wpa-mon.txt
sudo busctl --system tree fi.w1.wpa_supplicant1 | grep -i peers
```

## Tests

`linkd/test_miracast_linkd.py`: unit tests for the pure helpers (WFD IE
parsing, MAC/device-type decoding, state expiry/ordering), using the Fire TV and
`bedroom tv` records captured from this machine.

```sh
cd modules/miracast/linkd && python3 -m unittest test_miracast_linkd
```

`engine/test_wfd.py` (16 tests): framing, format parsing and selection.
`tests/engine_e2e.sh [gst]`: the engine against a mock TV on localhost.
`tests/run-portal-test.sh`: `portal_capture.py` against `mock_portal.py`
(session sequence, fd passing, user cancel).
(`gst` needs gst-launch-1.0 and the plugins on PATH; the Nix-built engine
already has them.)

`tests/`: an end-to-end check of the daemon and CLI against `mock_wpa.py`, a
fake wpa_supplicant on a private session bus (no root, no hardware):

```sh
cd modules/miracast/tests
nix shell --impure nixpkgs#dbus \
  --expr '(builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux.python3.withPackages (ps: [ ps.dbus-fast ])' \
  -c ./run-integration.sh
```

## File map

```
modules/miracast/
  README.md                 this file
  default.nix               NixOS module: services.miracast.*
  linkd/miracast_linkd.py   the root daemon (wpa_supplicant D-Bus <-> state/socket)
  linkd/test_miracast_linkd.py
  engine/miracast_source.py the source engine (RTSP session + GStreamer)
  engine/wfd.py             WFD protocol logic (pure, unit tested)
  engine/test_wfd.py
  ctl/miracast_ctl.py       coel-miracast CLI (stdlib only)
  tests/mock_wpa.py         fake wpa_supplicant for tests
  tests/mock_sink.py        fake Miracast TV for engine tests
  tests/engine_e2e.sh       engine vs mock TV (`gst` argument also streams)
  tests/mock_portal.py      fake ScreenCast portal;  run-portal-test.sh runs it
  ../castlib/portal_capture.py  xdg-desktop-portal ScreenCast client (shared with the Google Cast module)
  tests/integration.sh      end-to-end test; run-integration.sh sets up the bus
```

## Quality and audio (Nov 6)

- Fire TV advertises 1080p30 at H.264 level 3.1 (too low on paper) yet decodes it:
  the engine now trusts the advertised mode (`--strict-levels` restores the old
  behaviour) and encodes at the level the mode needs (4.0); bitrate default 12 Mbit/s.
  Fall back to 720p with `--preference 5`.
- Audio: if the sink offers AAC (it does), M4 selects `AAC 00000001 00` and the
  pipeline adds the default sink's monitor (`pipewiresrc stream.capture.sink=true`)
  -> `fdkaacenc` 128 kbit/s -> the same `mpegtsmux`. `--no-audio` disables it.
  Portal source only. LPCM was not implemented (private-stream framing).
- Latency is mostly the TV's own jitter buffer; our side is zerolatency x264 with
  no B-frames or lookahead.
- Fit, not stretch: `videoscale add-borders` alone still *stretches* (it negotiates a
  non-square pixel aspect ratio to fill the frame). The portal caps therefore pin
  `pixel-aspect-ratio=1/1`, which gives letter/pillarboxing (verified with a circle test pattern).
- Audio capture verified with a tone: the sink monitor delivers real samples. The
  monitor is a *copy*, so the laptop keeps playing locally while casting.
- The pixel-aspect-ratio pin above was not enough on its own: xdph's frames carry a
  bogus PAR (1/2147483647) and videoscale then stretches whatever follows. The portal
  chain now has `videoconvert ! capssetter caps=video/x-raw,pixel-aspect-ratio=1/1` first (capssetter directly after `pipewiresrc` breaks negotiation: "target not found") (reproduced
  with a synthetic 2256x1504 source: stretched -> correct).
- TS PIDs are pinned to the WFD spec values (video 0x1011, audio 0x1100) via
  `mux.sink_4113` / `mux.sink_4352`; mpegtsmux's defaults were different and some
  sinks only play audio from the spec PID. If audio is still silent, next suspects are
  LPCM instead of AAC and the sink's own volume/mute.

- Lesson learned: `coel-miracast cast` read the *previous* run's `miracast-source.json`
  (state=error) and killed the fresh engine within a second, so every retry after one
  failure repeated the old error. The CLI now deletes the status file before starting
  the engine. Also `coel-miracast stop` ends the cast (as documented); stopping a scan
  is now `coel-miracast scan-stop`.

## Performance (Nov 6, choppiness)

- Cause: the CPU pipeline ran as one serial chain (BGRA 2256x1504 -> scale -> convert -> x264) at
  only ~1.3x real time in a benchmark, so any extra load dropped frames.
- Fix: convert to I420 first (`videoconvert n-threads=4`), then scale, with `queue`s
  (`leaky=downstream`, 2-3 buffers) between convert / scale / encode so they run on separate
  cores and the stream drops frames rather than building up delay. ~4.6x real time in the
  same benchmark; a 7 s recording from a synthetic PipeWire source gave 199 frames
  (about 28 fps incl. startup) with the correct aspect.
- Experimental `--encoder va` (VA-API on the Radeon 760M: `vapostproc` fit-with-borders to BGRx
  then to NV12 -> `vah264enc`, ~2x faster still). Works with `videotestsrc` input, but frames
  coming from a PipeWire source came out flat in testing, so it is NOT the default. Note that
  `vapostproc add-borders` into NV12 gives green bars on this driver (do the border in BGRx), and
  without `pixel-aspect-ratio=1/1` in the caps it stretches.
- Remaining delay is mostly the TV's jitter buffer. Other knobs if needed: bitrate (`--bitrate`),
  `key-int-max`, 720p60 (`--preference 6`).

## Latency / smoothness measurements (Nov 6, second pass)

- Our side of the pipeline is not where the delay is: tracer latency ~17-34 ms (convert+scale+encode+mux),
  frames at a steady 30 fps (a recording had 208 frames over 6.9 s, in step with audio).
- mpegtsmux timestamps run ~125-165 ms ahead of the PCR (measured by parsing the TS); there is no mpegtsmux
  property for that, so the TV's playout buffer starts there. The rest is the TV's own jitter buffer.
- Bursts: an IDR at default x264 settings is ~260 KB (5x the average frame, ~170 ms of airtime at 12 Mbit/s),
  which is a plausible once-per-second stutter on Wi-Fi Direct. `vbv-buf-capacity` bounds it:
  600 ms -> IDR 260 KB, 150 -> 201 KB, 60 -> 83 KB (zone-plate test). Default is now `--vbv-ms 80`.
  `intra-refresh=true` removes IDR spikes entirely (max 72 KB) but is riskier for sinks; not enabled.
- Not implemented: honouring the sink's `wfd_idr_request` (needs engine control over the encoder; the gst-launch
  subprocess cannot be signalled). Losses therefore heal at the next periodic IDR (<= 1 s).

- `coel-miracast cast <name> --source portal [engine flags]` forwards any extra flags to the engine, e.g.
  `--encoder va`, `--bitrate 8000`, `--vbv-ms 60`, `--preference 5`, `--no-audio`, `--strict-levels`.

## Colour / sharpness investigation (Nov 6, third pass)

- The stream itself is colour-accurate: solid colours through the real encode chain decode (per their VUI tags,
  bt709 / limited range) to within 1-4 levels of the source. So "faded" on the TV points at how the TV treats the
  range/matrix, or at softness, not at corrupted colours. The I420-first and vbv changes were reverted anyway.
- New switches to test on the TV: `--color bt709|bt709-full|bt601` (changes both the conversion matrix and the
  VUI tags), `--source test --pattern smpte|colors|gradient|ball` (known colour bars to judge colours against).
  Example: `coel-miracast cast "Joel's Fire TV" --source test --pattern smpte --color bt709-full`
- Sharpness: x264 `ultrafast` disables the deblocking filter and sub-pel motion search; default is now
  `--preset veryfast` (same speed in a benchmark, ~12% smaller at equal settings) and the downscale uses
  lanczos. Limits we cannot change: the TV only advertises Constrained Baseline (no CABAC / B-frames), 4:2:0
  chroma, and the 3:2 panel is downscaled to 1620x1080.

- TV test results (Fire TV): `--color bt601` looks washed out and `--color bt709-full` too contrasty, i.e. the
  TV ignores the VUI tags and always decodes as BT.709 limited range, so the default (`bt709`) is the correct
  encoding. Remaining flatness is the TV picture / source, so a look adjustment is available:
  `--contrast 1.1 --saturation 1.15 --gamma 1.1 --brightness 0` (all default to "unchanged"; applied in YUV
  just before the encoder, software encoder only).

## Wi-Fi dropping after casting (Nov 6)

- Symptom: after casting, the normal Wi-Fi stays disconnected until reboot. Logs: when the TV's group is on
  another channel than the AP (TV chose 5200 MHz, AP is on 5745), mt7921 cannot hold both: the station is
  deauthenticated "by local choice" (and `Could not set interface p2p-wlp1s0-N flags (UP): Device or resource busy`).
  NetworkManager then logs `Activation: failed ... link timed out`; after its default 4 failures it **blocks
  autoconnect** for that profile, so it never reconnects (only a restart/reboot resets it).
- Fixes: (1) `services.miracast.keepStationAutoconnect` (default on) raises NetworkManager's
  `[main] autoconnect-retries-default` from 4 to 100 (the first attempt used `[connection] connection.autoconnect-retries`,
  which NetworkManager rejects as an unknown key). (2) linkd asks for the station's current channel in
  the first P2P Connect (`frequency` arg, from wpa's CurrentBSS), so no channel switch is needed when the TV
  accepts it; retries leave the channel to the TV. `--no-match-station-channel` disables it.
- Immediate workaround without a rebuild:
  `nmcli connection modify "Princess' Palace" connection.autoconnect-retries 0` (or `nmcli device connect wlp1s0`
  to reconnect by hand).
- Observed Nov 7: each P2P connect attempt (incl. each retry) deauthenticates the station "by local choice"
  (~10 s outage, then NM reconnects); `WPS-PBC-ACTIVE` follows on wlp1s0. The channel-matching request did not
  log "asking for the station's channel", so linkd now logs why the lookup failed. To see wpa_supplicant's reason:
  `sudo busctl set-property fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 DebugLevel s debug`
  then cast and read `journalctl -u wpa_supplicant-wlp1s0 | grep -i -E "conflict|disconnect"`; set it back to `info`.
- Root cause of the Wi-Fi drops on disconnect/stop (Nov 7, from wpa_supplicant debug logs): linkd called
  `P2PDevice.Disconnect` on the *main* interface (wlp1s0). wpa_supplicant implements that as "deauthenticate this
  interface" (`wlp1s0: Disconnected - do not scan`), so every `coel-miracast stop/disconnect` knocked the normal
  Wi-Fi off and left it waiting for NetworkManager. linkd now ends the group on the group's own interface
  (`GetInterface(ifname)` then `P2PDevice.Disconnect` there) and cancels a formation in progress with
  `P2PDevice.Cancel`. The mock + integration test assert that `Disconnect` never reaches the main interface.
- The channel request works (log: `asking for the station's channel (5745 MHz)`; wpa: `num_MCC=2`, forced
  freq 5745), so group formation itself no longer needs to move the station.
- Reminder: `nixos-rebuild switch` restarts NetworkManager when its config changes, which briefly drops Wi-Fi
  (that was the 00:06:42 disconnect).
- Nov 7, forced channel backfired: with `frequency` forced to the station's 5745 MHz the Fire TV acknowledged our
  GO Negotiation Requests (49 of 54 TX callbacks `success=1`) but never sent a Response, so the link sat in
  "connecting". The adapter reports `num_MCC=2` (two-channel concurrency), so forcing is not needed. It is now
  opt-in: `miracast-linkd --match-station-channel`. The real cause of the Wi-Fi drops was the Disconnect bug above.

## Roku (Nov 8)

- "Roku Express - 898" shows up as a sink (`group_capability` 3 = persistent + **already a group owner**,
  WFD port 7236, content protection advertised). A GO cannot do GO negotiation (our request just timed out), so
  linkd now **joins** its group (`P2PDevice.Connect` with `join=true`) whenever the peer's group capability has the
  GO bit (0x02); the Fire TV (capability 0) still negotiates. `coel-miracast connect/cast` need no flags;
  `{"join": true|false}` in the connect request overrides it.
- Needs a rebuild to take effect; Roku side: Settings > System > Screen mirroring (leave it on "Prompt" and
  accept the dialog, or "Always allow").
- Roku, first contact: the link came up (we joined its group, got 172.29.243.x) and then our M3 was answered
  `455 Method Not Valid In This State`. Strict sinks want their own M2 (OPTIONS) answered before the source's
  M3 GET_PARAMETER; the Fire TV does not care. The engine now waits (max 5 s) for the sink's M2 after M1.
- Roku blank screen (Nov 8): the stream itself is valid (local decode of the exact negotiated format: H.264 High 4.1
  1080p30 + AAC, PIDs 0x1011/0x1100) and ~24 MB went out, but the Roku showed nothing and sent no IDR requests.
  The Roku also wedges (`no response to SET_PARAMETER`) when M4 says `wfd_audio_codecs: none` (the `test`
  source used to send none), so the test source now sends silent AAC too. M4 now says `wfd_content_protection: none`
  when the sink advertises HDCP (Roku: `HDCP2.1 port=12000`), and the engine logs the M4 body and the SETUP headers.
  Next experiment: `coel-miracast cast Roku --source test --pattern smpte` to see whether any video shows.
- Stale groups (Nov 8): after the Disconnect fix, a cast that failed before the link was "ready" left its group
  interface (`p2p-wlp1s0-5`, UP with an IP) behind, and every later attempt died with
  `Could not set interface p2p-wlp1s0-N flags (UP): Device or resource busy` (the adapter has no free virtual
  interface). linkd now ends *every* `p2p-*` group interface (each on its own path) on `disconnect`/`stop`, and
  also before starting a new connection. Manual cleanup without a rebuild:
  `sudo systemctl restart wpa_supplicant-wlp1s0` (brief Wi-Fi drop) or `sudo iw dev p2p-wlp1s0-5 del`.

## Roku black screen with screen capture = oversized keyframes (Nov 8)

- The test pattern played on the Roku but real screen capture stayed black. Capturing the real screen through the
  same chain gave keyframes of **181 KB average** (a static desktop has ~11 KB P-frames, so the one keyframe per
  second is 15x larger, ~140 RTP packets in one burst) versus 55 KB for the test pattern. A small stick on Wi-Fi
  Direct drops part of that burst, so every IDR is damaged and nothing decodes (black). The Fire TV copes.
- `vbv-buf-capacity` caps it: 600 ms (x264 default) -> IDR 181 KB, 60 -> 80 KB, **30 -> 45 KB** (max 46 KB), and a
  static desktop is still crisp (later P-frames refine it). `--vbv-ms` now defaults to 30.
- If a sink still shows black: `--vbv-ms 20` or `--bitrate 8000`; intra-refresh (no IDR at all) is the next step.
- Regression (Nov 8): editing the `--vbv-ms` option with a slice replace deleted the neighbouring options
  (`--color`, `--pattern`, `--preset`, `--contrast`, ...), so `build_pipeline` raised AttributeError at PLAY. The
  read loop swallowed it, which looked like "sink closed the connection". Fixed: options restored, the parser is
  now `build_parser()`, a unit test builds every pipeline from default args, and unexpected handler errors are
  logged as `internal error: <traceback>` and set the engine status to error.
- Roku portal black screen, hypothesis (Nov 8): variants `--audio-source silence`, `--bitrate 3000` and
  `--preference 5` stayed black while the smpte test pattern played; stream parameters (profile/level/SPS/VUI/PIDs)
  are identical. What differs is the *data rate*: smpte has a noise block, so it never goes below several Mbit/s,
  whereas a static desktop is ~100-byte P-frames. A player that waits for a byte prebuffer never starts.
  `--mux-bitrate N` pads the transport stream with null packets to a constant N kbit/s (verified: a static
  smpte100 pattern goes from ~1 KB/frame to ~7.9 Mbit/s on the wire). Test: `--source test --pattern smpte100`
  (static, expect black without padding) then the same with `--mux-bitrate 8000`, then `--source portal --mux-bitrate 8000`.
- Static smpte100 (no padding) played fine on the Roku, so the low-data-rate theory is wrong (`--mux-bitrate` stays
  as an option). New diagnostic source `--source testcap [--pattern P]`: a synthetic 2256x1504 BGRA picture (with
  xdph's bogus pixel-aspect-ratio) through exactly the portal chain (videoconvert, capssetter, queue, lanczos
  videoscale + borders, videorate, queue, x264), no portal and no capture. Black = a chain element upsets the
  Roku; bars = the problem is specific to the real capture.
- Roku testcap bisect (Nov 8): `--source testcap` is black even with every optional stage removed, while `--source test`
  shows bars. Verified identical between the two: SPS/PPS bytes, NAL structure, PAT/PMT, PIDs, PTS-PCR, RTP headers
  (PT 33, contiguous seq, monotonic ts), first-video-packet time (~0.1 s), throughput (~11 Mbit/s). What is left is the
  picture path: BGRA vs I420, 2256x1504 vs 1920x1080, bogus PAR + `videoscale add-borders`.
  Diagnostics: `--cap-format I420|BGRA`, `--cap-size WxH`, `--chain-skip all`.
- Also seen: the Roku closes the RTSP connection exactly 60 s after PLAY in runs left running (session timeout=60
  that we advertise); check whether a keep-alive is needed.
- Keep-alive (Nov 8): the engine now sends M16 (`GET_PARAMETER` with the Session header) every 25 s while streaming.
  Before this the Roku closed the connection at exactly 60 s (`session over: sink closed the connection`).
- Start order hypothesis (Nov 8): in every stream the Roku plays (`--source test`) the first *video* timestamp is
  ~12-15 ms before the first audio one; in every stream it blacks out (testcap, portal, 20-65 ms) audio comes first.
  Everything else measured identical (see above). Switches to flip just that: `--video-ts-offset-ms N` /
  `--audio-ts-offset-ms N` (a `clocksync ts-offset` stage; test sources / silent audio). Locally `test
  --video-ts-offset-ms 100` becomes audio-first (+15 ms) and `testcap ... --audio-ts-offset-ms 100` becomes
  video-first (-22 ms). Roku A/B: A = `--source test --video-ts-offset-ms 100` (black if the hypothesis holds),
  B = `--source testcap --cap-format I420 --cap-size 1920x1080 --chain-skip all --audio-ts-offset-ms 100` (bars).

## What the documentation says (Nov 8) and what we changed

Sources: Wi-Fi Display spec as quoted in [GStreamer bug 729686](https://bugzilla.gnome.org/show_bug.cgi?id=729686)
(PMT PID 0x100, PCR PID 0x1000, video 0x1011, audio from 0x1100, PAT/PMT repeated at most every 100 ms);
gnome-network-displays' source (`wfd-media-factory.c`, `wfd-client.c`): M4 carries only video formats, audio
codecs, presentation URL and client RTP ports; keep-alive GET_PARAMETER every 25 s with a 30 s session timeout;
`mpegtsmux alignment=7`, `sink_4113`/`sink_4352`, `h264parse config-interval=-1`, x264 baseline/CBR/vbv 50 ms,
pipeline latency 500 ms with 500 ms queues in front of the muxer; PCR/PTS clock recovery on the sink side
(Miracast patents). Roku-specific protocol documentation does not exist publicly (Roku's support pages only cover
the Prompt / Always allow settings).

Our stream deviated from the spec in three ways, now fixed by default (`--no-ts-spec` reverts): PMT was on PID 0x20
(now 0x100), PAT/PMT gaps were up to 133 ms (now <= 67 ms: `pat-interval=pmt-interval=4500`), and the PCR rode on the
*audio* PID because that pad was created first (now `prog-map ... PCR_1=sink_4113`, i.e. video). `h264parse
config-interval=-1` as in GND. Not possible with mpegtsmux: a dedicated PCR PID 0x1000.

## Roku fix: start the audio after the video (Nov 8)

- Correction: the "first video timestamp comes before audio" note above was wrong (I had keyed on ffprobe's stream
  index, which swaps between runs). Measured by PID, audio's first PTS is earlier than video's in every stream.
- The real, reproducible difference (Roku A/B, repeated: bars every time with it, black every time without):
  holding the audio back ~100 ms (a `clocksync` stage) so that the **stream on the wire starts with video PES**
  instead of audio. With a heavier chain (screen scaling) more delay is needed, and `clocksync` on live
  PipeWire audio dropped ~85 % of the audio (78 of ~470 PES in 10 s), so it cannot be used for real audio.
- Implemented instead: the audio is captured in a **separate process** (`build_audio_cmd`, AAC ADTS on stdout) that the
  engine starts `--audio-start-delay-ms` (default 300) after the video pipeline; the main pipeline reads it with
  `fdsrc do-timestamp=true ! aacparse ! mux.sink_4352`. Verified: stream starts with 7-9 video PES, full audio
  (369 of ~375 PES in 8 s), a tone through the system sink decodes intact (peak ~9000), video flow unchanged.
  Timestamps are arrival times, so lip-sync is unaffected.
- Portal check (Nov 8): with the helper starting at 300 ms the real screen still blacked out on the Roku. Measured with the
  real capture: first video TS packet at 0.45 s (pipewire connect + first frame), first audio 0.48 s, i.e. only ~2 video
  frames ahead (PES order `VVAVAAVAAV`). The working bars case has >= 3 video frames before the first audio (`VVVA...`).
  Default `--audio-start-delay-ms` is now 1000 (portal: 9+ video frames first). If the Roku still shows black, vary it
  (`--audio-start-delay-ms 2000`) before looking elsewhere.
- `--audio-source off`: AAC negotiated but no audio sent (the Roku hangs on M4 `wfd_audio_codecs: none`, i.e. `--no-audio`: 'no response to SET_PARAMETER'); for isolating audio from the video problem.
- Status (Nov 8): the Roku shows the screen with `--audio-source off` and with the default (audio helper started 1 s
  after the video), but no sound is heard. `--audio-source tone` (440 Hz) added to tell "Roku does not play our AAC"
  apart from "system capture / timing problem": `--source test --pattern smpte --audio-source tone`.
- Roku audio (Nov 8): the 440 Hz tone is not played, so the Roku does not accept our AAC as packaged. AOSP's Wi-Fi Display
  source ([TSPacketizer.cpp](https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-8.1.0_r1/media/libstagefright/wifi-display/source/TSPacketizer.cpp),
  the reference Android phones cast to Roku with): AAC = stream_type 0x0F, stream_id 0xC0, 7-byte ADTS header `FF F9`
  (ID=1 MPEG-2, protection_absent=1), PES with data_alignment, one access unit per PES, PTS only; PCR on its own PID with
  adaptation-only packets; LPCM = stream_type 0x83, stream_id 0xBD, a 2-byte PMT descriptor (tag 0x83: sampling-frequency
  code<<5 | 3<<1, then 0x2f for stereo), no extra PES header in that version. Ours differed in the ADTS ID bit
  (fdkaacenc writes `FF F1`; aacparse cannot convert it). The engine now relays the audio helper's output and sets the
  ID bit (`wfd.adts_to_mpeg2`, `--aac-mpeg4-adts` keeps the old form). Verified in the real stream: header `fff94c80...`,
  tone decodes (6.4 s, peak ~9900). Next if still silent: LPCM per the AOSP layout (needs a custom PMT descriptor).

## Root cause of the Roku black screen and missing audio: the first PMT (Nov 8)

The Roku reads the program map table (PMT) **once, at the start**, and only plays the elementary streams listed in it.
`mpegtsmux` lists a stream only once its pad has caps, so the first PMT contained whichever stream produced data first:

| stream | first PMT (`scripts`: pmtscan) | Roku |
|---|---|---|
| `--source test` (both pads ready immediately) | video + audio, packet #3 | plays |
| in-process audio, portal/testcap (audio data first) | **audio only** (video added in v1 later) | black screen |
| audio started late via helper + `aacparse` (caps only after the first frame) | **video only** (audio added in v1 ~0.5 s later) | picture, no sound |
| audio relayed one-ADTS-frame-per-UDP-datagram into `udpsrc caps=...adts,framed=true` | **video + audio, version 0** | expected: picture and sound |

That also explains every earlier "experiment" (audio delay via `clocksync`, `--audio-source off`, start order): they
only changed which stream was in the first table. Fix: the audio branch is `udpsrc ... caps=audio/mpeg,mpegversion=2,
stream-format=adts,framed=true,rate=48000,channels=2 ! mux.sink_4352`; the engine relays the capture process' AAC
(MPEG-2 ADTS) frames to it. Verified with the mock sink (`--dump`): first PMT lists `0x1b@0x1011` and `0x0f@0x1100` for audio start
delays of 0 and 1000 ms, tone decodes, video intact. `--audio-start-delay-ms` stays at 1000 so the first *data* is video (a
data-first stream may still list only itself).

## Display profiles and audio codec negotiation (Nov 8)

**Capabilities are negotiated, quirks are declared.** Video and audio formats come from what the display advertises in
M3 (`wfd_video_formats`, `wfd_audio_codecs`). What a display needs *beyond* that cannot be discovered, so it lives in
per-display **profiles** (`engine/profiles.py`), plain data matched after M3:

```
services.miracast.sinkProfiles.bedroom-tv = {
  match    = { name = "bedroom"; };                      # regexes (case-insensitive), ANDed
  settings = { bitrate = 8000; audio_preference = "AAC,LPCM"; };   # engine options by argparse name
};
```

- Match fields: `name`, `manufacturer`, `model`, `device_type` (Wi-Fi Direct peer record from miracast-linkd's
  state.json), `content_protection`, `audio_codecs` (the display's advert). Empty `match` = every display.
- Order: your profiles, then the built-ins (`roku`, `fire-tv`: documented, currently no overrides because the engine
  defaults already encode what we learned: first-PMT audio+video, M16 keep-alive, M2-before-M3, ...). First match wins.
- Command-line options beat a profile. JSON file: `coel-miracast cast ... --profiles FILE` or `$MIRACAST_PROFILES` (the
  Nix option sets it for `coel-miracast`). The engine logs `profile: <name> (applied {...})` and publishes
  `sink_profile` in its status.
- **Audio**: `--audio-preference AAC,LPCM` (default `AAC`): the first codec in the list that the display offers *in a mode we
  can produce* (AAC-LC 48 kHz stereo; LPCM 16-bit 48 kHz stereo) is negotiated; none -> `wfd_audio_codecs: none`.
  **LPCM is experimental**: it goes through `mpegtsmux`'s `audio/x-lpcm` (Blu-ray style, PMT stream_type 0x8b here),
  while AOSP's source uses stream_type 0x83 with a 2-byte PMT descriptor. The first PMT lists the stream and the
  pipeline runs (verified with the mock sink), but no real display has been tried. So it is only used when you put it
  in the preference list.
- Both displays so far offer AAC, which is what they get; the audio format was never the Roku/Fire TV difference.

## Google Cast

Implemented as a sibling module, `modules/gcast` (`coel-gcast`), sharing only `modules/castlib/portal_capture.py` with this one.
HLS-over-HTTP plus the CASTV2 control protocol, tested against a mock device only; see its README.

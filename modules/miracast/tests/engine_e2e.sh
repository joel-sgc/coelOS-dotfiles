#!/usr/bin/env bash
# Engine end to end against the mock sink, on localhost. No root, no hardware.
#   ./engine_e2e.sh            negotiation only (--source none)
#   ./engine_e2e.sh gst        also stream a test pattern (needs gst-launch-1.0 + x264/mpegts plugins on PATH)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$work"' EXIT
source=none; listen=3
if [ "${1:-}" = gst ]; then source=test; listen=4; fi

# --idle-timeout is shorter than the session on purpose: it must only apply while
# waiting for the TV, not cut a running stream off (a real bug: streams ended at 180s).
python3 "$here/../engine/miracast_source.py" --port 17236 --source "$source" --idle-timeout 2 \
    --status-file "$work/status.json" > "$work/engine.log" 2>&1 &
sleep 1
report=$(python3 "$here/mock_sink.py" --port 17236 --rtp-port 19000 --listen-seconds "$listen")
echo "sink saw: $report"
sleep 0.5
echo "engine status: $(cat "$work/status.json")"
python3 - "$report" "$source" <<'PY'
import json, sys
r = json.loads(sys.argv[1]); src = sys.argv[2]
assert not r["errors"], r["errors"]
assert r["play_status"] == 200, r
assert r["setup_reply"]["status"] == 200, r
assert r["play_status"] == 200 and not r["errors"], r   # the session outlived --idle-timeout
assert "server_port=5000" in r["setup_reply"]["transport"], r
m4 = r["m4"]
assert m4["wfd_video_formats"].startswith("00 00 02 08 00000080"), m4      # CHP, 4.1, 1080p30 (bit 7)
assert m4["wfd_presentation_URL"].startswith("rtsp://127.0.0.1/wfd1.0/streamid=0"), m4
assert m4["wfd_client_rtp_ports"].split()[1] == "19000", m4
if src == "test":
    assert r["udp_packets"] > 10, "no stream received: %s" % r
    assert r["first_payload_sync"] is True, "RTP payload is not MPEG-TS: %s" % r
print("OK")
PY
echo "--- engine log"; cat "$work/engine.log"

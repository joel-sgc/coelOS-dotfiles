#!/usr/bin/env bash
# End-to-end test of miracast-linkd + coel-miracast against the mock wpa_supplicant,
# on a private session bus. No root, no hardware.
#   nix shell nixpkgs#dbus nixpkgs#python3Packages.dbus-fast -c ./integration.sh   (or via the flake check)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$work"' EXIT
trap 'echo "--- FAILED; logs:"; cat "$work/linkd.log" "$work/mock.log" 2>/dev/null' ERR
export MIRACAST_STATE="$work/state.json" MIRACAST_SOCKET="$work/linkd.sock"

python3 "$here/mock_wpa.py" > "$work/mock.log" 2>&1 &
sleep 1
python3 "$here/../linkd/miracast_linkd.py" --bus session --group "$(id -gn)" \
    --state-file "$MIRACAST_STATE" --socket "$MIRACAST_SOCKET" --device-name test-laptop > "$work/linkd.log" 2>&1 &
sleep 2
ctl="python3 $here/../ctl/miracast_ctl.py"

echo "--- status (before scan)"; $ctl status
echo "--- scan";                  $ctl scan 20
sleep 3
echo "--- peers";                 $ctl peers
$ctl peers | grep -q "Joel's Fire TV"
$ctl peers | grep -q "bedroom tv"
echo "--- state json (excerpt)";  $ctl json | head -30
echo "--- connect: the mock fails every formation, so expect 3 attempts then an error"
$ctl connect fire 2>&1 | head -2
for _ in $(seq 20); do
  $ctl json | python3 -c "import sys,json; l=json.load(sys.stdin)['link']; sys.exit(0 if l['state']=='error' else 1)" && break
  sleep 1
done
$ctl json | python3 -c "
import sys, json
l = json.load(sys.stdin)['link']
print('link:', l)
assert l['state'] == 'error' and 'gave up after 3 attempts' in l['reason'], l"
echo "--- disconnect must not touch the main interface (it would drop the station's Wi-Fi)"
$ctl disconnect >/dev/null
! grep -q "Disconnect on main" "$work/mock.log"
grep -q "Disconnect on group" "$work/mock.log"          # ...but a leftover group interface is ended
echo "--- logs"; cat "$work/linkd.log"; cat "$work/mock.log"
echo "OK"

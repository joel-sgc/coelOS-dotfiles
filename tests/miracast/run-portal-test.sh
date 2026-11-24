#!/usr/bin/env bash
# portal_capture against a mock portal on a private session bus.
#   nix shell --impure --expr '(builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux.dbus' \
#     --expr '(builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux.python3.withPackages (ps: [ ps.dbus-fast ])' \
#     -c ./run-portal-test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$work"' EXIT
cat > "$work/bus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=$work/bus</listen><auth>EXTERNAL</auth>
  <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
CONF
dbus-daemon --config-file="$work/bus.conf" --nofork &
for _ in $(seq 20); do [ -S "$work/bus" ] && break; sleep 0.2; done
export DBUS_SESSION_BUS_ADDRESS="unix:path=$work/bus"
python3 "$here/portal_e2e.py"

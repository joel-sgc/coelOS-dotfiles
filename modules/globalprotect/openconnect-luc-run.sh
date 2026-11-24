# coel-openconnect-luc-run: root-side half of the openconnect backend.
# Invoked by systemd as `openconnect-luc@<uid>.service`'s ExecStart ("%i" is
# the instance -- the uid of the user who authenticated). Reads the session
# file that coel-vpn-connect's unprivileged authenticate phase wrote to that
# user's own runtime dir, feeds the cookie to openconnect on stdin (never on
# argv -- argv is visible to any user via /proc or `systemctl status`), and
# execs into it so systemd tracks the real openconnect PID.
#
# $HIP_WRAPPER is exported by the Nix wrapper around this script -- the
# store path of coel-openconnect-hipreport (modules/globalprotect-openconnect.nix).
#
# Env: GP_IFACE   tunnel interface name (default gpd0, matches vpn-routes.sh)

uid="${1:?usage: coel-openconnect-luc-run <uid>}"
session_file="/run/user/$uid/coel-openconnect-luc-session"
iface="${GP_IFACE:-gpd0}"

# A device named $iface can be left behind persistent (survives its owning
# process dying -- confirmed via `ip -d link show gpd0` showing `persist
# on`) by the vendor client, or by a previous openconnect run that crashed
# after creating the tun but before this process exited. Either way,
# openconnect's own TUNSETIFF then fails with "Device or resource busy"
# trying to create a device under the same name. We run as root here, so
# clear it unconditionally before every attempt; harmless if it's already
# gone.
ip link delete dev "$iface" >/dev/null 2>&1 || true

if [ ! -r "$session_file" ]; then
  echo "coel-openconnect-luc-run: no session file at $session_file" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$session_file"
set +a
rm -f "$session_file"

: "${COOKIE:?session file had no COOKIE}"
target="${CONNECT_URL:-${HOST:?session file had neither CONNECT_URL nor HOST}}"

args=(
  --protocol=gp
  --interface="$iface"
  --csd-wrapper="$HIP_WRAPPER"
  --cookie-on-stdin
  --pid-file=/run/openconnect-luc.pid
)
[ -n "${FINGERPRINT:-}" ] && args+=(--servercert="$FINGERPRINT")
[ -n "${RESOLVE:-}" ] && args+=(--resolve="$RESOLVE")

exec openconnect "${args[@]}" "$target" <<< "$COOKIE"

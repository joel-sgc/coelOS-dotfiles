# coel-vpn-routes: reconcile policy routing so Tailscale (with an exit node),
# GlobalProtect (full tunnel) and the local LAN coexist.
#
# Why this is needed: GP is a pure full tunnel (`default via gpd0 metric 10`
# in the main table). A Tailscale exit node installs `default dev tailscale0`
# in table 52, and its ip rule (priority 5270) consults table 52 BEFORE main,
# so GP's routes are never reached and its traffic just disappears.
#
# Kernel route lookup is "first matching rule whose table has a matching
# route wins" -- there is no per-packet retry, but a rule whose table has no
# route for the destination falls through to the next rule. So the "priority
# order" is expressed as rules, most specific intent first:
#
#   100  local LAN subnets, multicast (mDNS), link-local, GP gateway host
#        route                                          -> table 100
#   110  Tailscale's specific routes (peers, 100.64/10, accepted subnet
#        routes) but NOT its exit-node default          -> table 52, suppress /0
#   120  LUC ranges (GP_RANGES)                          -> table 101 (dev gpd0)
#   5270 (tailscale's own) everything else               -> exit node
#
# Run as `coel-vpn-routes` (reconcile once) or `coel-vpn-routes watch`.
# DRY=1 prints the commands instead of running them.
# Env: GP_RANGES  space-separated prefixes that must go through GlobalProtect

LAN_TABLE=100
GP_TABLE=101
PRIO_LAN=100
PRIO_GW=105
PRIO_TS=110
PRIO_GP=120
VPN_IFS='^(gpd0|tailscale0|lo|virbr.*|docker.*|br-.*|veth.*)$'

run() { if [ -n "${DRY:-}" ]; then echo "+ $*"; else "$@"; fi; }

clear_ours() {
  run ip route flush table "$LAN_TABLE" 2>/dev/null || true
  run ip route flush table "$GP_TABLE" 2>/dev/null || true
  local p
  for p in $PRIO_LAN $PRIO_GW $PRIO_TS $PRIO_GP; do
    while ip rule show | grep -q "^$p:"; do
      run ip rule del priority "$p" || break
      [ -n "${DRY:-}" ] && break
    done
  done
}

reconcile() {
  clear_ours

  # --- local LAN: every connected subnet on a real interface --------------
  local metric=0 dev subnet ifs=()
  while read -r subnet dev; do
    [ -n "$subnet" ] || continue
    if [[ "$dev" =~ $VPN_IFS ]]; then continue; fi
    run ip route replace "$subnet" dev "$dev" table "$LAN_TABLE"
    run ip rule add to "$subnet" lookup "$LAN_TABLE" priority "$PRIO_LAN"
    ifs+=("$dev")
  done < <(ip -j -4 route show scope link proto kernel | jq -r '.[] | select(.dst != null) | "\(.dst) \(.dev)"')

  # mDNS / multicast and link-local, once per real interface. Without this
  # the exit-node default swallows them (and Avahi sees nothing).
  for dev in "${ifs[@]}"; do
    metric=$((metric + 1))
    run ip route replace 224.0.0.0/4 dev "$dev" metric "$metric" table "$LAN_TABLE"
    run ip route replace 169.254.0.0/16 dev "$dev" metric "$metric" table "$LAN_TABLE"
  done
  if [ "${#ifs[@]}" -gt 0 ]; then
    run ip rule add to 224.0.0.0/4 lookup "$LAN_TABLE" priority "$PRIO_LAN"
    run ip rule add to 169.254.0.0/16 lookup "$LAN_TABLE" priority "$PRIO_LAN"
  fi

  # --- GlobalProtect up? ---------------------------------------------------
  if ip -4 -br addr show dev gpd0 2>/dev/null | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
    # The gateway's own transport traffic must keep using the real uplink
    # (GP installs a /32 host route for it in main); otherwise it would be
    # captured by the exit node or the LUC range below and loop.
    local gw
    for gw in $(ip -j -4 route show | jq -r '.[] | select((.dst // "") | test("^[0-9.]+(/32)?$")) | select(.dev != "gpd0" and .dev != "tailscale0") | .dst'); do
      run ip rule add to "${gw%/32}/32" lookup main priority "$PRIO_GW"
    done

    local r
    for r in ${GP_RANGES:-}; do
      run ip route replace "$r" dev gpd0 table "$GP_TABLE"
    done
    run ip rule add lookup "$GP_TABLE" priority "$PRIO_GP"
  fi

  # --- Tailscale's specific routes, never its exit-node default ------------
  if ip link show tailscale0 >/dev/null 2>&1; then
    run ip rule add lookup 52 suppress_prefixlength 0 priority "$PRIO_TS"
  fi
}

case "${1:-once}" in
  once) reconcile ;;
  down) clear_ours ;;
  watch)
    # Signature of everything reconcile() reads (main-table routes, addresses,
    # whether tailscale0 exists). Our own writes only touch tables 100/101 and
    # rules, so they never change it -- no self-trigger loop.
    sig() { { ip -4 route show table main; ip -4 -br addr; ip -br link; } | grep -v -E '^(lo|virbr|docker)' | sha256sum; }
    reconcile
    last=$(sig)
    ip monitor link address route | while read -r _; do
      while read -r -t 1 _; do :; done
      cur=$(sig)
      [ "$cur" = "$last" ] && continue
      last=$cur
      reconcile || true
    done
    ;;
  *) echo "usage: coel-vpn-routes [once|watch|down]" >&2; exit 2 ;;
esac

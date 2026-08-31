TABLE=100
ACTION="${1:?Usage: gp-route-fix <up|down>}"

if [ "$ACTION" = "down" ]; then
  ip route flush table "$TABLE" 2>/dev/null || true
  while pri=$(ip rule show | grep "lookup $TABLE" | head -1 | cut -d: -f1); [ -n "$pri" ]; do
    ip rule del priority "$pri"
  done
  exit 0
fi

# gpd0 can exist for a moment before PanGPS finishes configuring its
# routes, so retry briefly instead of assuming it's ready immediately.
for _ in $(seq 1 15); do
  routes=$(ip -j -4 route show)
  gpd0_subnets=$(echo "$routes" | jq -r '.[] | select(.dev=="gpd0" and (.dst // "") != "" and .dst != "default") | .dst')

  fixed_any=0
  for subnet in $gpd0_subnets; do
    real_iface=$(echo "$routes" | jq -r --arg s "$subnet" '.[] | select(.dst==$s and .dev!="gpd0") | .dev' | head -1)
    [ -z "$real_iface" ] && continue

    fixed_any=1
    ip route show table "$TABLE" | grep -qF "$subnet dev $real_iface" || \
      ip route add "$subnet" dev "$real_iface" table "$TABLE"
    ip rule show | grep -qF "to $subnet lookup $TABLE" || \
      ip rule add to "$subnet" table "$TABLE" priority 100
  done

  [ "$fixed_any" = "1" ] && exit 0
  sleep 1
done

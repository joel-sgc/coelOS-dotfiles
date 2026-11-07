#!/bin/sh
# Collector for EthernetBackend.qml: prints one tab-separated record per line.
#   IF  dev type state conn carrier speed mac kind chip parent vid
#   CF  dev key value        profile settings of the device's active/known connection
#   LIVE dev key value       runtime addressing (nmcli device show)
#   CT  dev rx tx            byte counters
#   RT  <ip route line>      every IPv4 route
#   LS  dev <lease line>     NetworkManager shared-mode dnsmasq leases
#   NB  ip state             ip neighbour table
#   DV  dev type state conn  every non-wired device (wifi, tunnels), for upstream names
# Wired devices only (ethernet + vlan). Needs nmcli and ip.

T=$(printf '\t')
CFIELDS="ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.route-metric,ipv4.never-default,ipv6.method,802-3-ethernet.mtu,802-3-ethernet.cloned-mac-address,802-3-ethernet.wake-on-lan,connection.autoconnect,connection.metered,connection.lldp,connection.master,connection.timestamp,802-1x.eap,802-1x.identity,vlan.parent,vlan.id"

emit_conn() { # dev conn
  [ -n "$2" ] || return 0
  nmcli -t -f "$CFIELDS" connection show "$2" 2>/dev/null | while IFS= read -r l; do
    printf 'CF\t%s\t%s\t%s\n' "$1" "${l%%:*}" "${l#*:}"
  done
}

emit_if() { # dev type state conn
  dev=$1 type=$2 state=$3 conn=$4
  carrier=$(cat "/sys/class/net/$dev/carrier" 2>/dev/null)
  speed=$(cat "/sys/class/net/$dev/speed" 2>/dev/null)
  mac=$(cat "/sys/class/net/$dev/address" 2>/dev/null)
  parent= vid= chip= kind=
  if [ "$type" = vlan ]; then
    kind=vlan
    parent=$(nmcli -g vlan.parent connection show "$conn" 2>/dev/null)
    vid=$(nmcli -g vlan.id connection show "$conn" 2>/dev/null)
  else
    sub=$(basename "$(readlink "/sys/class/net/$dev/device/subsystem" 2>/dev/null)" 2>/dev/null)
    case "$sub" in usb) kind=usb ;; pci) kind=onboard ;; *) kind=${sub:-ethernet} ;; esac
    chip=$(udevadm info -q property -p "/sys/class/net/$dev" 2>/dev/null | sed -n 's/^ID_MODEL_FROM_DATABASE=//p' | head -n 1)
    [ -n "$chip" ] || chip=$(basename "$(readlink "/sys/class/net/$dev/device/driver" 2>/dev/null)" 2>/dev/null)
  fi
  printf 'IF\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$dev" "$type" "$state" "$conn" "$carrier" "$speed" "$mac" "$kind" "$chip" "$parent" "$vid"
  emit_conn "$dev" "$conn"
  nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS device show "$dev" 2>/dev/null | while IFS= read -r l; do
    printf 'LIVE\t%s\t%s\t%s\n' "$dev" "${l%%:*}" "${l#*:}"
  done
  printf 'CT\t%s\t%s\t%s\n' "$dev" "$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null)" "$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null)"
  if [ -r "/var/lib/NetworkManager/dnsmasq-$dev.leases" ]; then
    while IFS= read -r l; do printf 'LS\t%s\t%s\n' "$dev" "$l"; done < "/var/lib/NetworkManager/dnsmasq-$dev.leases"
  fi
}

seen=" "
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | while IFS=: read -r dev type state conn; do
  case "$type" in ethernet|vlan) ;; *) continue ;; esac
  emit_if "$dev" "$type" "$state" "$conn"
done

# VLAN profiles whose device is down don't show up in `device status`.
nmcli -t -f NAME,TYPE,DEVICE,ACTIVE connection show 2>/dev/null | while IFS=: read -r name type dev active; do
  [ "$type" = vlan ] && [ "$active" != yes ] || continue
  vdev=$(nmcli -g connection.interface-name connection show "$name" 2>/dev/null)
  printf 'IF\t%s\tvlan\tdisconnected\t%s\t\t\t\tvlan\t\t%s\t%s\n' "$vdev" "$name" "$(nmcli -g vlan.parent connection show "$name" 2>/dev/null)" "$(nmcli -g vlan.id connection show "$name" 2>/dev/null)"
  emit_conn "$vdev" "$name"
done

nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | while IFS=: read -r dev type state conn; do
  case "$type" in ethernet|vlan) ;; *) printf 'DV\t%s\t%s\t%s\t%s\n' "$dev" "$type" "$state" "$conn" ;; esac
done

ip -4 route show 2>/dev/null | while IFS= read -r l; do printf 'RT\t%s\n' "$l"; done
ip -4 neigh show 2>/dev/null | while read -r ip _ dev _ _ st; do printf 'NB\t%s\t%s\n' "$ip" "$st"; done

#!/usr/bin/env bash
#
# --csd-wrapper for `openconnect --protocol=gp`.
#
# Structured like the stock openconnect hipreport.sh template (see
# ../../testing/hipreport.sh for that version): same --cookie/--client-ip/--md5
# argument handling and the same user/domain/computer extraction from the
# cookie. The difference is the report body. The stock template fabricates a
# Windows 10 + McAfee + BitLocker host that doesn't exist. This script
# queries the *real* machine openconnect is running on and reports what it
# actually finds -- same principle as the old vendor client's sandbox-
# visibility fix (make real state visible to the check, not a substitute
# for it; see [[project_globalprotect_luc]] -- that sandbox is gone too).
#
# Cross-checked field-for-field against a genuine report the vendored
# PanGpHip binary produced for this same host (captured at
# /var/lib/globalprotect/pan_gp_hrpt.xml) so the schema and the host-info
# shape match what LUC's gateway already accepts from this machine.
#
# openconnect calls this with:
#   --cookie      URL-encoded login cookie (from --authenticate --protocol=gp)
#   --client-ip   IPv4 openconnect was assigned by the gateway
#   --md5         md5 the gateway expects echoed back in the report

set -euo pipefail

COOKIE=
IP=
MD5=

while [ "${1:-}" ]; do
    case "$1" in
        --cookie)    shift; COOKIE="$1" ;;
        --client-ip) shift; IP="$1" ;;
        --md5)       shift; MD5="$1" ;;
    esac
    shift || true
done

if [ -z "$COOKIE" ] || [ -z "$IP" ] || [ -z "$MD5" ]; then
    echo "Parameters --cookie, --client-ip, and --md5 are required" >&2
    exit 1
fi

# Extract username/domain/computer from the cookie, same fields the stock
# template pulls out.
urldecode() { printf '%b' "${1//%/\\x}"; }

GP_USER=$(echo "$COOKIE" | sed -rn 's/(.+&|^)user=([^&]+)(&.+|$)/\2/p')
DOMAIN=$(echo "$COOKIE" | sed -rn 's/(.+&|^)domain=([^&]+)(&.+|$)/\2/p')
COMPUTER=$(echo "$COOKIE" | sed -rn 's/(.+&|^)computer=([^&]+)(&.+|$)/\2/p')
GP_USER=$(urldecode "$GP_USER")
DOMAIN=$(urldecode "$DOMAIN")
COMPUTER=$(urldecode "$COMPUTER")
[ -n "$COMPUTER" ] || COMPUTER=$(hostname)

NOW=$(date +'%m/%d/%Y %H:%M:%S')

# Stable per-machine id, derived from this machine's real /etc/machine-id
# rather than invented -- a genuine (if reformatted) identifier of this
# actual host, not a placeholder like the stock template's deadbeef UUID.
if [ -r /etc/machine-id ]; then
    MID=$(cat /etc/machine-id)
    HOSTID=$(printf '%s' "$MID" | md5sum | sed -E \
        's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/\1-\2-\3-\4-\5/')
else
    HOSTID="00000000-0000-0000-0000-000000000000"
fi

OS_INFO="Linux $(uname -r)"

# Report the software actually doing the connecting, not a client we're not
# running.
OC_VERSION=""
if command -v openconnect >/dev/null 2>&1; then
    OC_VERSION=$(openconnect --version 2>&1 | head -1 | awk '{print $2}') || true
fi
CLIENT_VERSION="openconnect-${OC_VERSION:-unknown}"

# Real primary interface (the one with the default route), its real MAC and
# real local addresses -- not the VPN-assigned $IP, which goes in the
# top-level <ip-address> field below, matching how the genuine PanGpHip
# report separates the two.
IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1); exit}')
MAC=""
IFACE_IP4=""
IFACE_IP6=""
if [ -n "$IFACE" ]; then
    [ -r "/sys/class/net/$IFACE/address" ] && MAC=$(cat "/sys/class/net/$IFACE/address")
    IFACE_IP4=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    IFACE_IP6=$(ip -6 addr show "$IFACE" scope link 2>/dev/null | awk '/inet6/{print $2}' | cut -d/ -f1 | head -1)
fi

# Live firewall state. firewalld on this host runs on an nftables backend
# (see configuration.nix); iptables-legacy is present but inert/superseded
# -- check both live rather than assume either.
NFT_VERSION=$(nft --version 2>/dev/null | awk '{print $2}' | sed 's/^v//' || true)
IPT_VERSION=$(iptables --version 2>/dev/null | awk '{print $2}' | sed 's/^v//' || true)
NFT_ENABLED="no"
if systemctl is-active --quiet nftables 2>/dev/null || systemctl is-active --quiet firewalld 2>/dev/null; then
    NFT_ENABLED="yes"
fi
IPT_ENABLED="no"
if systemctl is-active --quiet iptables 2>/dev/null; then
    IPT_ENABLED="yes"
fi

# No AV installed on this host -- report that honestly as an empty list
# (matches the real PanGpHip report), rather than claiming a product that
# isn't there.
ANTIMALWARE_XML="        <list>
        </list>"
if systemctl is-active --quiet clamav-daemon 2>/dev/null; then
    ANTIMALWARE_XML='        <list>
            <entry>
                <ProductInfo>
                    <Prod vendor="Cisco" name="ClamAV"/>
                    <real-time-protection>yes</real-time-protection>
                </ProductInfo>
            </entry>
        </list>'
fi

cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<hip-report name="hip-report">
	<md5-sum>$MD5</md5-sum>
	<user-name>$GP_USER</user-name>
	<domain>$DOMAIN</domain>
	<host-name>$COMPUTER</host-name>
	<host-id>$HOSTID</host-id>
	<ip-address>$IP</ip-address>
	<ipv6-address></ipv6-address>
	<generate-time>$NOW</generate-time>
	<hip-report-version>4</hip-report-version>
	<categories>
		<entry name="host-info">
			<client-version>$CLIENT_VERSION</client-version>
			<os>$OS_INFO</os>
			<os-vendor>Linux</os-vendor>
			<domain>$DOMAIN</domain>
			<host-name>$COMPUTER</host-name>
			<host-id>$HOSTID</host-id>
			<network-interface>
				<entry name="${IFACE:-unknown}">
					<description>${IFACE:-unknown}</description>
					<mac-address>${MAC}</mac-address>
					<ip-address>
						<entry name="${IFACE_IP4}"/>
					</ip-address>
					<ipv6-address>
						<entry name="${IFACE_IP6}"/>
					</ipv6-address>
				</entry>
			</network-interface>
		</entry>
		<entry name="anti-malware">
$ANTIMALWARE_XML
		</entry>
		<entry name="firewall">
			<list>
				<entry>
					<ProductInfo>
						<Prod vendor="IPTables" name="IPTables" version="${IPT_VERSION}"/>
						<is-enabled>$IPT_ENABLED</is-enabled>
					</ProductInfo>
				</entry>
				<entry>
					<ProductInfo>
						<Prod vendor="The Netfilter Project" name="nftables" version="${NFT_VERSION}"/>
						<is-enabled>$NFT_ENABLED</is-enabled>
					</ProductInfo>
				</entry>
			</list>
		</entry>
	</categories>
</hip-report>
EOF

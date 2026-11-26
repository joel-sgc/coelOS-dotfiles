# coel-bambu-setup: the Bambu printer's address and LAN access code, kept in the
# login keyring (Secret Service) for home/quickshell/scripts/coel-bambu.py (the island printer daemon).
#
#   coel-bambu-setup          ask for host / serial / access code and store them
#   coel-bambu-setup get      print the stored entry as JSON (what the daemon reads)
#   coel-bambu-setup forget   delete it

ATTRS=(service coel-bambu account printer)

case "${1:-}" in
  get)
    secret-tool lookup "${ATTRS[@]}"
    exit $?
    ;;
  forget)
    secret-tool clear "${ATTRS[@]}"
    echo "Removed the printer from the keyring."
    exit 0
    ;;
  "" | set) ;;
  *)
    cat >&2 <<'EOF'
coel-bambu-setup          ask for host / serial / access code and store them
coel-bambu-setup get      print the stored entry as JSON
coel-bambu-setup forget   delete it
EOF
    exit 2
    ;;
esac

echo "Bambu printer setup. Values are on the printer: Settings > WLAN (IP, access code)"
echo "and Settings > Device (serial). It must be in LAN-only mode with Developer Mode on"
echo "for pause/resume/stop to work."
echo
read -r -p "Host or IP (as reachable over Tailscale): " host
read -r -p "Serial number: " serial
read -r -s -p "Access code: " code
echo
read -r -p "Display name [Bambu P1S]: " name
name=${name:-Bambu P1S}

if [[ -z "$host" || -z "$serial" || -z "$code" ]]; then
  echo "Host, serial and access code are all required." >&2
  exit 1
fi

jq -cn --arg host "$host" --arg serial "$serial" --arg code "$code" --arg name "$name" \
  '{host: $host, serial: $serial, access_code: $code, name: $name}' |
  secret-tool store --label="Bambu printer (coelOS island)" "${ATTRS[@]}"

echo "Stored. The island picks it up within a minute (or reload Quickshell)."

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "./Phosphor.js" as Phosphor

// ===== NETWORK DROPDOWN =====
// Phase 4b: real data/actions, replacing phase 4a's hardcoded layout.
//
// Wifi device/network list, connect/disconnect/forget/connect-with-
// password, and scan control are all real, via Quickshell.Networking
// (same as Network.qml's bar icon). Everything Quickshell doesn't expose
// -- band/channel per network, the connected-network's gateway/DNS/MAC,
// hotspot -- goes through nmcli instead, the same "shell out for what the
// native API doesn't cover" pattern PowerDropdown.qml (voltage/cycles)
// and BluetoothDropdown.qml (bluetoothctl agent) already use.
//
// Network editing (password, autoconnect, manual IP/gateway/DNS,
// cloned-MAC, forget) and hotspot (ssid/password/band/hidden) are all
// real, via `nmcli connection modify` -- only fires for the fields that
// actually changed from the profile's real prefetched values (see
// openEdit's profileDetailsProc), and only forces a reconnect when the
// edited network is the one currently active, since applying most of
// these to an already-active connection is a no-op otherwise.
//
// TODO(network editing): no client-side validation on the manual
// address/gateway/dns fields -- nmcli's own rejection of bad input
// surfaces via netError, but there's no format hinting beyond the field
// placeholders.
//
// "Share from a specific interface" was never a real nmcli hotspot
// setting to begin with -- NetworkManager's hotspot mode NATs clients
// through whichever connection already provides the default route
// automatically, there's no flag to pick one -- so that field now just
// reports the real upstream instead of pretending to be a choice.
//
// VPN section doesn't match the design mock's generic "VPN connections"
// list because there's nothing real to list that way here -- this
// machine has no actual NetworkManager VPN connections (checked: `nmcli
// connection show` lists none). What it does have is GlobalProtect (via
// the existing coel-vpn-* wrapper scripts already in this repo) and
// Tailscale, so that's what's shown instead: two specific, real
// services, not a generic list. GlobalProtect's connect flow is
// genuinely interactive (coel-vpn-connect's own documented contract:
// GP_STATUS: lines on stdout, an MFA code read from stdin when needed),
// so it runs as a real monitored Process with an inline MFA prompt, not
// a fire-and-forget command.
//
// Rows that mix several fixed-width text columns (the network list) use
// manual x positioning, not RowLayout -- see PowerDropdown.qml's
// profile-row comment for why.
Item {
  id: dropdownRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  // Set by Panel.qml from the containing Popup's `open` -- drives wifi
  // scanning so this isn't burning power scanning while nobody's
  // actually looking at the dropdown (it's eagerly instantiated the
  // moment the bar starts, not lazily created on first open).
  property bool popupOpen: false
  // Reclaims keyboard focus from whatever field last had it (e.g. a
  // password TextInput in the edit view) every time the popup opens --
  // without this, an invisible-but-still-focused TextInput from a prior
  // session silently swallows every keypress meant for j/k/e/d/tab in
  // the main view, since a hidden item doesn't lose activeFocus just by
  // becoming invisible.
  onPopupOpenChanged: if (popupOpen) dropdownRoot.forceActiveFocus()

  signal closeRequested()

  property string view: "main"

  // ----- real wifi/wired device + network list -----
  readonly property var wifiDevice: {
    for (const dev of Networking.devices.values) {
      if (dev.type === DeviceType.Wifi) return dev;
    }
    return null;
  }
  readonly property var wiredDevice: {
    for (const dev of Networking.devices.values) {
      if (dev.type === DeviceType.Wired) return dev;
    }
    return null;
  }
  readonly property string ifaceName: wifiDevice ? wifiDevice.name : (wiredDevice ? wiredDevice.name : "—")

  // Only actually scans while this dropdown's popup is open and showing
  // the main view -- no point burning radio/CPU scanning for a screen
  // nobody's looking at.
  Binding {
    target: dropdownRoot.wifiDevice
    property: "scannerEnabled"
    value: dropdownRoot.popupOpen && dropdownRoot.view === "main"
    when: dropdownRoot.wifiDevice !== null
  }
  readonly property bool scanning: wifiDevice ? wifiDevice.scannerEnabled : false

  function secShort(sec) {
    switch (sec) {
      case WifiSecurityType.Open: return "open";
      case WifiSecurityType.Owe: return "owe";
      case WifiSecurityType.Wpa3SuiteB192: return "wpa3";
      case WifiSecurityType.Sae: return "wpa3";
      case WifiSecurityType.Wpa2Psk: return "wpa2";
      case WifiSecurityType.Wpa2Eap: return "wpa2-ent";
      case WifiSecurityType.WpaPsk: return "wpa";
      case WifiSecurityType.WpaEap: return "wpa-ent";
      case WifiSecurityType.StaticWep:
      case WifiSecurityType.DynamicWep: return "wep";
      case WifiSecurityType.Leap: return "leap";
      default: return "unknown";
    }
  }

  // Band/channel per SSID -- not exposed by Quickshell.Networking at all,
  // polled from nmcli's own scan cache instead. Keyed by SSID (dedupe by
  // strongest signal, same as the network list itself effectively is).
  property var scanDetails: ({})
  Process {
    id: scanDetailsProc
    command: ["sh", "-c", "nmcli -t -f SSID,CHAN,FREQ device wifi list ifname '" + dropdownRoot.ifaceName + "' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const details = {};
        for (const line of text.split("\n")) {
          const parts = line.split(":");
          if (parts.length < 3) continue;
          const ssid = parts[0], chan = parts[1], freqStr = parts[2];
          if (!ssid) continue;
          const freq = parseInt(freqStr);
          const band = freq >= 4900 ? "5 GHz" : "2.4 GHz";
          if (!details[ssid]) details[ssid] = { band, channel: chan };
        }
        dropdownRoot.scanDetails = details;
      }
    }
  }
  Timer {
    interval: 8000
    running: dropdownRoot.popupOpen && dropdownRoot.view === "main" && dropdownRoot.ifaceName !== "—"
    repeat: true
    triggeredOnStart: true
    onTriggered: scanDetailsProc.running = true
  }

  readonly property var allNetworks: {
    const out = [];
    if (!wifiDevice || !wifiDevice.networks) return out;
    for (const n of wifiDevice.networks.values) {
      const detail = scanDetails[n.name] || {};
      out.push({
        network: n,
        ssid: n.name,
        sec: secShort(n.security),
        sig: Math.round(n.signalStrength * 100),
        connected: n.connected,
        known: n.known,
        connecting: n.state === ConnectionState.Connecting,
        band: detail.band || "—",
        channel: detail.channel || "—",
      });
    }
    return out;
  }
  readonly property var currentEntry: {
    for (const e of allNetworks) if (e.connected) return e;
    return null;
  }
  readonly property var availableNetworks: {
    const avail = allNetworks.filter(e => !e.connected);
    // Known (saved) networks first, so a network you've already used
    // doesn't get buried under whatever nearby signal spam a scan turns
    // up -- Array.sort is stable (ES2019+), so order within each group
    // is otherwise untouched.
    avail.sort((a, b) => (b.known ? 1 : 0) - (a.known ? 1 : 0));
    return avail;
  }
  onAvailableNetworksChanged: sel = Math.max(0, Math.min(sel, availableNetworks.length - 1))

  function sigColor(sig) { return sig >= 65 ? colors[3] : sig >= 40 ? colors[2] : colors[1]; }
  function bars(sig) {
    const b = sig >= 75 ? 4 : sig >= 50 ? 3 : sig >= 25 ? 2 : 1;
    const g = "▂▄▆█";
    return { strong: g.slice(0, b), weak: g.slice(b) };
  }

  property int sel: 0
  // Which block of the main view j/k/enter/space act on -- "networks" or
  // "vpn" -- toggled with Tab, same paired/nearby-section split
  // BluetoothDropdown.qml already uses for its own Tab handling.
  property string section: "networks"
  property int vpnSel: 0 // 0 = GlobalProtect, 1 = Tailscale

  function connect(entry) {
    if (!entry || !entry.network) return;
    if (entry.known || entry.sec === "open") entry.network.connect();
    else openEdit(entry, "connect");
  }
  function disconnectCurrent() {
    if (currentEntry && currentEntry.network) currentEntry.network.disconnect();
  }
  function rescanNow() { scanDetailsProc.running = true; }

  // ----- connected-network detail (nmcli, not in Quickshell.Networking) -----
  property var ifaceDetails: ({})
  Process {
    id: ifaceDetailsProc
    command: ["sh", "-c", "nmcli -t -f GENERAL.HWADDR,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS device show '" + dropdownRoot.ifaceName + "' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const d = { dns: [] };
        for (const line of text.split("\n")) {
          const idx = line.indexOf(":");
          if (idx < 0) continue;
          const key = line.slice(0, idx), val = line.slice(idx + 1);
          if (key === "GENERAL.HWADDR") d.mac = val;
          else if (key === "IP4.GATEWAY") d.gateway = val;
          else if (key.startsWith("IP4.DNS")) d.dns.push(val);
          else if (key.startsWith("IP6.ADDRESS")) d.ipv6 = val.split("/")[0];
        }
        dropdownRoot.ifaceDetails = d;
      }
    }
  }
  Timer {
    interval: 10000
    running: dropdownRoot.popupOpen && dropdownRoot.currentEntry !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: ifaceDetailsProc.running = true
  }

  // ----- uptime: tracked locally, not from nmcli -- nmcli's own
  // connection.timestamp is when the *profile* was last activated, which
  // doesn't reliably reset across reconnects/roaming the way "how long
  // has this session been up" should. Set once when currentEntry goes
  // from disconnected to connected (or switches SSID), ticked forward
  // every second purely in JS (no process spawn needed for a clock).
  property double connectedSinceMs: 0
  property string lastConnectedSsid: ""
  onCurrentEntryChanged: {
    const ssid = currentEntry ? currentEntry.ssid : "";
    if (ssid !== lastConnectedSsid) {
      connectedSinceMs = currentEntry ? Date.now() : 0;
      lastConnectedSsid = ssid;
    }
  }
  property int uptimeTick: 0
  Timer {
    interval: 1000
    running: dropdownRoot.popupOpen && dropdownRoot.currentEntry !== null
    repeat: true
    onTriggered: dropdownRoot.uptimeTick++
  }
  function formatUptime(ms) {
    if (ms <= 0) return "—";
    const totalSec = Math.floor(ms / 1000);
    const h = Math.floor(totalSec / 3600), m = Math.floor((totalSec % 3600) / 60), s = totalSec % 60;
    if (h > 0) return h + "h " + m + "m";
    if (m > 0) return m + "m " + s + "s";
    return s + "s";
  }
  readonly property string uptimeText: {
    uptimeTick; // referenced only to force this binding to re-evaluate every tick
    return connectedSinceMs > 0 ? formatUptime(Date.now() - connectedSinceMs) : "—";
  }

  // ----- throughput: real interface byte counters from sysfs, sampled
  // and diffed -- same "shell out for what Quickshell doesn't expose"
  // pattern as everything else here, just via `cat` on a counter file
  // instead of nmcli. Not reset on SSID change (rx_bytes/tx_bytes are
  // cumulative per-*interface*, not per-connection, so a plain delta
  // between polls is correct regardless of which network is active) --
  // only reset if the interface itself changes, since a residual delta
  // across two different NICs would be meaningless.
  property real rxRate: 0
  property real txRate: 0
  property double lastRxBytes: -1
  property double lastTxBytes: -1
  property double lastSampleTimeMs: 0
  onIfaceNameChanged: { lastRxBytes = -1; lastTxBytes = -1; lastSampleTimeMs = 0; rxRate = 0; txRate = 0; }
  Process {
    id: throughputProc
    command: ["sh", "-c", "cat '/sys/class/net/" + dropdownRoot.ifaceName + "/statistics/rx_bytes' '/sys/class/net/" + dropdownRoot.ifaceName + "/statistics/tx_bytes' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");
        if (lines.length < 2) return;
        const rx = parseFloat(lines[0]), tx = parseFloat(lines[1]);
        const now = Date.now();
        if (dropdownRoot.lastSampleTimeMs > 0 && rx >= dropdownRoot.lastRxBytes && tx >= dropdownRoot.lastTxBytes) {
          const dt = (now - dropdownRoot.lastSampleTimeMs) / 1000;
          if (dt > 0) {
            dropdownRoot.rxRate = (rx - dropdownRoot.lastRxBytes) / dt;
            dropdownRoot.txRate = (tx - dropdownRoot.lastTxBytes) / dt;
          }
        }
        dropdownRoot.lastRxBytes = rx;
        dropdownRoot.lastTxBytes = tx;
        dropdownRoot.lastSampleTimeMs = now;
      }
    }
  }
  Timer {
    interval: 2000
    running: dropdownRoot.popupOpen && dropdownRoot.currentEntry !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: throughputProc.running = true
  }
  function formatRate(bytesPerSec) {
    // Padded to a fixed 4-char column (monospace font, so this actually
    // lines up) so the ↓/↑ numbers don't jitter the rest of the row
    // sideways as their digit count changes between polls.
    let num, unit;
    if (bytesPerSec < 1024) { num = bytesPerSec.toFixed(0); unit = "B/s"; }
    else if (bytesPerSec < 1024 * 1024) { num = (bytesPerSec / 1024).toFixed(1); unit = "KB/s"; }
    else { num = (bytesPerSec / 1024 / 1024).toFixed(1); unit = "MB/s"; }
    return num.padStart(4, " ") + " " + unit;
  }

  // ----- edit view: password, autoconnect, ip config, MAC, forget are
  // all real -----
  property var draft: null
  function openEdit(entry, mode) {
    if (!entry) return;
    netError = "";
    const m = mode || "edit";
    draft = {
      entry, ssid: entry.ssid, sec: entry.sec, pass: "", show: false,
      ipMode: "Automatic (DHCP)", addr: "", gw: "", dns: "",
      origIpMode: "Automatic (DHCP)", origAddr: "", origGw: "", origDns: "",
      mac: "Stable", origMac: "Stable",
      auto: true, mode: m,
    };
    view = "edit";
    // Only an already-known network has a real nmcli profile to read --
    // a brand-new "connect" attempt doesn't get one until after the
    // first successful connect, so there's nothing to prefetch yet.
    if (m === "edit") {
      profileDetailsProc.command = ["nmcli", "-t", "-f",
        "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,wifi.cloned-mac-address,connection.autoconnect",
        "connection", "show", entry.ssid];
      profileDetailsProc.running = true;
    }
  }
  Process {
    id: profileDetailsProc
    stdout: StdioCollector {
      onStreamFinished: {
        if (!dropdownRoot.draft) return;
        const d = {};
        for (const line of text.split("\n")) {
          const idx = line.indexOf(":");
          if (idx < 0) continue;
          d[line.slice(0, idx)] = line.slice(idx + 1);
        }
        const ipMode = d["ipv4.method"] === "manual" ? "Manual" : "Automatic (DHCP)";
        const addr = (d["ipv4.addresses"] || "").split(",")[0] || "";
        const gw = d["ipv4.gateway"] || "";
        const dns = (d["ipv4.dns"] || "").split(",").filter(s => s.length > 0).join(" ");
        const mac = (d["wifi.cloned-mac-address"] || "").trim() === "random" ? "Random" : "Stable";
        const auto = d["connection.autoconnect"] !== "no";
        dropdownRoot.draft = Object.assign({}, dropdownRoot.draft, {
          ipMode, addr, gw, dns, origIpMode: ipMode, origAddr: addr, origGw: gw, origDns: dns,
          mac, origMac: mac, auto,
        });
      }
    }
  }
  function setDraft(patch) { draft = Object.assign({}, draft, patch); }

  // Password, IP config and MAC changes for a network you're already
  // connected/saved to aren't something Quickshell.Networking exposes --
  // WifiNetwork.connectWithPsk() supplies a psk for a fresh connection
  // attempt, it doesn't update or otherwise touch a saved profile. The
  // only real path for any of this is nmcli connection-modify, then
  // reactivating it.
  //
  // A plain entry.network.connect() alone isn't enough to apply any of
  // this when the network is already connected -- NetworkManager treats
  // activating an already-active connection as a no-op. Bringing it down
  // first forces a real reactivation, which does pick up the changes.
  // Only done when the edited network is the one currently connected
  // (entry.connected) -- an autoconnect-only change, or editing a
  // network you're not actively on, doesn't need to disrupt anything.
  //
  // Every nmcli argument here is passed as a literal argv element, never
  // interpolated into a shell string -- SSIDs come from nearby broadcast
  // APs (effectively untrusted input; anyone can name their AP
  // `'; rm -rf ~ #`), so building a `sh -c` string out of one would be a
  // real command-injection hole.
  property var pendingReconnectNetwork: null
  property string netError: ""
  Process {
    id: networkModifyProc
    stderr: StdioCollector {
      onStreamFinished: dropdownRoot.netError = text.trim()
    }
    onExited: {
      if (dropdownRoot.pendingReconnectNetwork) {
        reconnectDownProc.command = ["nmcli", "connection", "down", dropdownRoot.pendingReconnectNetwork.name];
        reconnectDownProc.running = true;
      }
    }
  }
  Process {
    id: reconnectDownProc
    onExited: {
      if (dropdownRoot.pendingReconnectNetwork) {
        dropdownRoot.pendingReconnectNetwork.connect();
        dropdownRoot.pendingReconnectNetwork = null;
      }
    }
  }

  function saveDraft() {
    if (!draft) return;
    const entry = draft.entry, shouldConnect = draft.mode === "connect";
    if (entry && entry.network) {
      if (shouldConnect && draft.sec !== "open" && entry.network.connectWithPsk) {
        entry.network.connectWithPsk(draft.pass);
      } else if (shouldConnect) {
        entry.network.connect();
      } else if (draft.mode === "edit") {
        const modifyArgs = ["nmcli", "connection", "modify", entry.ssid];
        let needsReconnect = false;

        if (draft.sec !== "open" && draft.pass.length > 0) {
          modifyArgs.push("wifi-sec.psk", draft.pass);
          needsReconnect = true;
        }
        if (draft.ipMode !== draft.origIpMode || draft.addr !== draft.origAddr ||
            draft.gw !== draft.origGw || draft.dns !== draft.origDns) {
          if (draft.ipMode === "Manual") {
            modifyArgs.push("ipv4.method", "manual", "ipv4.addresses", draft.addr, "ipv4.gateway", draft.gw, "ipv4.dns", draft.dns);
          } else {
            modifyArgs.push("ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", "", "ipv4.dns", "");
          }
          needsReconnect = true;
        }
        if (draft.mac !== draft.origMac) {
          modifyArgs.push("wifi.cloned-mac-address", draft.mac === "Random" ? "random" : "stable");
          needsReconnect = true;
        }

        if (modifyArgs.length > 4) {
          dropdownRoot.pendingReconnectNetwork = (needsReconnect && entry.connected) ? entry.network : null;
          networkModifyProc.command = modifyArgs;
          networkModifyProc.running = true;
        }
      }
      // Autoconnect is a real nmcli connection setting (Quickshell.
      // Networking's own `autoconnect` property lives on the *device*,
      // not per saved network profile, so it can't express "autoconnect
      // to this specific SSID").
      autoconnectProc.command = ["nmcli", "connection", "modify", entry.ssid, "connection.autoconnect", draft.auto ? "yes" : "no"];
      autoconnectProc.running = true;
    }
    view = "main";
    draft = null;
    dropdownRoot.forceActiveFocus();
  }
  function forgetDraft() {
    if (!draft) return;
    const entry = draft.entry;
    if (entry && entry.network) entry.network.forget();
    view = "main";
    draft = null;
    dropdownRoot.forceActiveFocus();
  }
  function backMain() {
    view = "main";
    draft = null;
    dropdownRoot.forceActiveFocus();
  }
  Process { id: autoconnectProc }

  function cyc(list, v) {
    const i = list.indexOf(v);
    return list[(i + 1) % list.length];
  }

  // ----- VPN: GlobalProtect (coel-vpn-*) + Tailscale -- see header
  // comment for why this isn't a generic connection list -----
  property string gpStatus: "unknown"
  property bool gpBusy: false
  property string gpMfaPrompt: ""
  property string gpMfaInput: ""
  Process {
    id: gpStatusProc
    command: ["coel-vpn-status"]
    stdout: StdioCollector {
      onStreamFinished: dropdownRoot.gpStatus = text.trim() || "unknown"
    }
  }
  Timer {
    interval: 5000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!dropdownRoot.gpBusy) gpStatusProc.running = true
  }
  Process {
    id: gpConnectProc
    command: ["coel-vpn-connect"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: (line) => {
        if (line.indexOf("GP_STATUS:") !== 0) return;
        const state = line.slice("GP_STATUS:".length).trim();
        if (state === "mfa-required") {
          dropdownRoot.gpMfaPrompt = "enter MFA code";
        } else {
          dropdownRoot.gpMfaPrompt = "";
          dropdownRoot.gpStatus = state;
        }
      }
    }
    onExited: {
      dropdownRoot.gpBusy = false;
      dropdownRoot.gpMfaPrompt = "";
      gpStatusProc.running = true;
    }
  }
  function gpToggle() {
    if (gpBusy) return;
    if (gpStatus === "connected" || gpStatus === "connected-internal") {
      gpBusy = true;
      const p = gpDisconnectProc;
      p.running = true;
    } else {
      gpBusy = true;
      gpMfaPrompt = "";
      gpConnectProc.running = true;
    }
  }
  Process {
    id: gpDisconnectProc
    command: ["coel-vpn-disconnect"]
    onExited: { dropdownRoot.gpBusy = false; gpStatusProc.running = true; }
  }
  function gpSubmitMfa() {
    if (!gpMfaPrompt) return;
    gpConnectProc.write(gpMfaInput + "\n");
    gpMfaInput = "";
    gpMfaPrompt = "";
  }

  property string tsStatus: "unknown"
  property var tsIps: []
  property bool tsBusy: false
  Process {
    id: tsStatusProc
    command: ["sh", "-c", "tailscale status --json 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const j = JSON.parse(text);
          dropdownRoot.tsStatus = j.BackendState || "unknown";
          dropdownRoot.tsIps = j.TailscaleIPs || [];
        } catch (e) {
          dropdownRoot.tsStatus = "unknown";
        }
      }
    }
  }
  Timer {
    interval: 5000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!dropdownRoot.tsBusy) tsStatusProc.running = true
  }
  Process {
    id: tsToggleProc
    onExited: { dropdownRoot.tsBusy = false; tsStatusProc.running = true; }
  }
  function tsToggle() {
    if (tsBusy) return;
    tsBusy = true;
    tsToggleProc.command = ["tailscale", tsStatus === "Running" ? "down" : "up"];
    tsToggleProc.running = true;
  }

  // ----- hotspot: ssid/password/band/hidden real via nmcli -----
  //
  // "On" is never set optimistically -- it's derived from a real nmcli
  // poll (hsActiveConn), so a failed start (bad driver support, missing
  // polkit permission, whatever) shows up as *staying off* with an error
  // message instead of the UI claiming success while nothing actually
  // happened. That mismatch (UI says on, nmcli never came up) is what
  // "gets stuck" without this -- earlier version flipped hs.on the
  // instant the command was launched, before knowing whether it worked.
  //
  // Band defaults to 2.4 GHz, not 5 GHz: confirmed live on this laptop's
  // real hardware (MediaTek mt7921e) that 5 GHz AP mode reliably fails
  // with "802.1X supplicant took too long to authenticate" /
  // "Hotspot network creation took too long" in NetworkManager's own log
  // -- the driver never even emits an AP-mode kernel event, so the
  // interface never actually comes up. 2.4 GHz activated successfully in
  // the same test. Still left as a real cycle (not hardcoded away)
  // since this is hardware-specific, not a universal nmcli limitation.
  property var hs: ({ ssid: "coel-hotspot", sec: "WPA2 Personal", pass: "nebula-7731", show: false, band: "2.4 GHz", hidden: false, busy: false, error: "" })

  property string hsActiveConn: ""
  readonly property bool hsOn: hsActiveConn === "Hotspot"
  Process {
    id: hotspotStateProc
    command: ["sh", "-c", "nmcli -t -f GENERAL.CONNECTION device show '" + dropdownRoot.ifaceName + "' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const idx = text.indexOf(":");
        dropdownRoot.hsActiveConn = idx >= 0 ? text.slice(idx + 1).trim() : "";
      }
    }
  }
  Timer {
    interval: 3000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: hotspotStateProc.running = true
  }

  // "Share from" isn't a real nmcli hotspot setting -- NetworkManager's
  // hotspot mode (ipv4.method=shared) NATs clients through whichever
  // connection is currently providing the default route automatically;
  // there's no flag to pick a specific upstream interface. So instead of
  // a fake selectable field that would silently do nothing, this polls
  // for a real connected ethernet device and just reports it.
  property string hsShareIface: ""
  Process {
    id: hsShareProc
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        let found = "";
        for (const line of text.split("\n")) {
          const parts = line.split(":");
          if (parts.length < 3) continue;
          if (parts[1] === "ethernet" && parts[2].indexOf("connected") === 0) { found = parts[0]; break; }
        }
        dropdownRoot.hsShareIface = found;
      }
    }
  }
  Timer {
    interval: 5000
    running: dropdownRoot.popupOpen && dropdownRoot.view === "hotspot"
    repeat: true
    triggeredOnStart: true
    onTriggered: hsShareProc.running = true
  }

  // Connected-devices list: NetworkManager's shared-mode hotspot runs
  // its own dnsmasq for DHCP, which keeps a real lease file at
  // /var/lib/NetworkManager/dnsmasq-<iface>.leases -- world-readable,
  // one line per lease as "<expiry-epoch> <mac> <ip> <hostname>
  // <client-id>" (confirmed live: a phone that joined during testing
  // showed up there with its real hostname). That's the actual source
  // of ip+mac+name; ip-neigh is only cross-referenced on top of it for
  // a live/idle indicator, not as the primary source.
  property var hsClients: []
  property var hsNeighStates: ({})
  onHsOnChanged: if (!hsOn) { hsClients = []; hsNeighStates = ({}); }
  Process {
    id: hsLeasesProc
    command: ["sh", "-c", "cat '/var/lib/NetworkManager/dnsmasq-" + dropdownRoot.ifaceName + ".leases' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const now = Math.floor(Date.now() / 1000);
        const clients = [];
        for (const line of text.split("\n")) {
          const parts = line.trim().split(/\s+/);
          if (parts.length < 4) continue;
          const expiry = parseInt(parts[0]);
          if (!isNaN(expiry) && expiry > 0 && expiry < now) continue;
          clients.push({ mac: parts[1], ip: parts[2], name: parts[3] === "*" ? "unknown device" : parts[3] });
        }
        dropdownRoot.hsClients = clients;
      }
    }
  }
  Process {
    id: hsNeighProc
    command: ["ip", "-4", "neigh", "show", "dev", dropdownRoot.ifaceName]
    stdout: StdioCollector {
      onStreamFinished: {
        const states = {};
        for (const line of text.split("\n")) {
          const parts = line.trim().split(/\s+/);
          if (parts.length < 2) continue;
          states[parts[0]] = parts[parts.length - 1];
        }
        dropdownRoot.hsNeighStates = states;
      }
    }
  }
  Timer {
    interval: 4000
    running: dropdownRoot.popupOpen && dropdownRoot.view === "hotspot" && dropdownRoot.hsOn
    repeat: true
    triggeredOnStart: true
    onTriggered: { hsLeasesProc.running = true; hsNeighProc.running = true; }
  }
  readonly property var hsClientRows: hsClients.map(c => ({
    mac: c.mac, ip: c.ip, name: c.name,
    online: ["REACHABLE", "STALE", "DELAY", "PROBE"].indexOf(hsNeighStates[c.ip] || "") >= 0,
  }))

  Process {
    id: hotspotStartProc
    stderr: StdioCollector {
      onStreamFinished: dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { error: text.trim() })
    }
    onExited: {
      // 802-11-wireless.hidden isn't a `device wifi hotspot` flag --
      // that helper doesn't expose it, so hidden mode needs a follow-up
      // connection-modify plus a reconnect to actually take effect (the
      // AP already started broadcasting its SSID by the time this
      // command returns). Safe to cycle down/up here specifically
      // because hotspot mode already means the station connection is
      // sacrificed for the duration -- unlike the station-network
      // password-change reconnect, this can't additionally knock the
      // user's regular wifi offline.
      if (dropdownRoot.hs.hidden) {
        hotspotHiddenProc.running = true;
      } else {
        dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { busy: false });
        hotspotStateProc.running = true;
      }
    }
  }
  Process {
    id: hotspotHiddenProc
    command: ["nmcli", "connection", "modify", "Hotspot", "802-11-wireless.hidden", "yes"]
    onExited: hotspotHiddenReapplyProc.running = true
  }
  Process {
    id: hotspotHiddenReapplyProc
    command: ["nmcli", "connection", "up", "Hotspot"]
    stderr: StdioCollector {
      onStreamFinished: dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { error: text.trim() })
    }
    onExited: {
      dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { busy: false });
      hotspotStateProc.running = true;
    }
  }
  Process {
    id: hotspotStopProc
    command: ["nmcli", "connection", "down", "Hotspot"]
    stderr: StdioCollector {
      onStreamFinished: dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { error: text.trim() })
    }
    onExited: {
      dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { busy: false });
      hotspotStateProc.running = true;
    }
  }
  function toggleHotspot() {
    if (hs.busy) return;
    hs = Object.assign({}, hs, { busy: true, error: "" });
    if (hsOn) {
      hotspotStopProc.running = true;
    } else {
      const bandArg = hs.band === "5 GHz" ? "a" : "bg";
      hotspotStartProc.command = ["nmcli", "device", "wifi", "hotspot", "ifname", ifaceName, "con-name", "Hotspot", "ssid", hs.ssid, "band", bandArg, "password", hs.pass];
      hotspotStartProc.running = true;
    }
  }

  focus: true
  Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Escape) {
      if (view !== "main") { backMain(); event.accepted = true; }
      else event.accepted = false;
      return;
    }
    if (event.key === Qt.Key_1) { view = "main"; draft = null; dropdownRoot.forceActiveFocus(); event.accepted = true; return; }
    if (event.key === Qt.Key_2) { view = "hotspot"; draft = null; dropdownRoot.forceActiveFocus(); event.accepted = true; return; }

    if (view === "main") {
      event.accepted = true;
      // Both Key_Tab and Key_Backtab are handled defensively -- same
      // caveat as BluetoothDropdown.qml's shift+tab handling: which one
      // actually arrives wasn't independently verified, so both are
      // covered and just toggle the same two-section split either way.
      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        section = section === "networks" ? "vpn" : "networks";
        return;
      }
      switch (event.key) {
        case Qt.Key_J:
        case Qt.Key_Down:
          if (section === "networks") sel = Math.min(availableNetworks.length - 1, sel + 1);
          else vpnSel = Math.min(1, vpnSel + 1);
          break;
        case Qt.Key_K:
        case Qt.Key_Up:
          if (section === "networks") sel = Math.max(0, sel - 1);
          else vpnSel = Math.max(0, vpnSel - 1);
          break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
          if (section === "networks") { if (availableNetworks[sel]) connect(availableNetworks[sel]); }
          else { if (vpnSel === 0) gpToggle(); else tsToggle(); }
          break;
        case Qt.Key_Space:
          if (section === "vpn") { if (vpnSel === 0) gpToggle(); else tsToggle(); }
          else event.accepted = false;
          break;
        case Qt.Key_E:
          if (section === "networks") {
            if (currentEntry) openEdit(currentEntry, "edit");
            else if (availableNetworks[sel]) openEdit(availableNetworks[sel], "connect");
          }
          break;
        case Qt.Key_D:
          if (section === "networks" && currentEntry) disconnectCurrent();
          break;
        case Qt.Key_R:
          if (section === "networks") rescanNow();
          break;
        default:
          event.accepted = false;
      }
    } else if (view === "edit") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { saveDraft(); event.accepted = true; }
    } else if (view === "hotspot") {
      if (event.key === Qt.Key_Space) { toggleHotspot(); event.accepted = true; }
    }
  }

  implicitWidth: 468
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: 0

    // ----- header -----
    RowLayout {
      width: parent.width
      height: 28

      RowLayout {
        spacing: 8
        Text {
          text: "network"
          color: dropdownRoot.colors[0]
          font.family: "JetBrains Mono"
          font.weight: Font.DemiBold
          font.pixelSize: 13
        }
        Text {
          text: "─ " + dropdownRoot.ifaceName + " ─"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
        Text {
          readonly property bool connectingAny: dropdownRoot.currentEntry === null && dropdownRoot.allNetworks.some(e => e.connecting)
          text: dropdownRoot.hsOn ? "◉ hotspot" : connectingAny ? "… connecting" : dropdownRoot.currentEntry ? "● online" : "○ offline"
          color: dropdownRoot.hsOn ? "#d19a66" : connectingAny ? dropdownRoot.colors[2] : dropdownRoot.currentEntry ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        implicitWidth: wifiTabLabel.implicitWidth + 16
        implicitHeight: 20
        radius: 2
        color: (dropdownRoot.view === "main" || dropdownRoot.view === "edit") ? dropdownRoot.hoverColor : "transparent"
        Text {
          id: wifiTabLabel
          anchors.centerIn: parent
          text: "1 wifi"
          color: dropdownRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { dropdownRoot.view = "main"; dropdownRoot.draft = null; dropdownRoot.forceActiveFocus(); } }
      }
      Rectangle {
        implicitWidth: hsTabLabel.implicitWidth + 16
        implicitHeight: 20
        radius: 2
        color: dropdownRoot.view === "hotspot" ? dropdownRoot.hoverColor : "transparent"
        Text {
          id: hsTabLabel
          anchors.centerIn: parent
          text: "2 hotspot"
          color: dropdownRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { dropdownRoot.view = "hotspot"; dropdownRoot.draft = null; dropdownRoot.forceActiveFocus(); } }
      }
      Text {
        text: "[×]"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.PointingHandCursor
          onClicked: dropdownRoot.closeRequested()
        }
      }
    }

    // ===== MAIN VIEW =====
    Column {
      visible: dropdownRoot.view === "main"
      width: parent.width
      spacing: 16

      Section {
        width: parent.width
        label: "connected"
        labelColor: dropdownRoot.currentEntry ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
        paddingTop: 12
        paddingBottom: 8
        paddingSide: 10
        spacing: 6

        RowLayout {
          visible: dropdownRoot.currentEntry !== null
          width: parent.width
          Row {
            spacing: 8
            Text { text: "●"; color: dropdownRoot.colors[3]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            Text { text: dropdownRoot.currentEntry ? dropdownRoot.currentEntry.ssid : ""; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
            Text {
              text: dropdownRoot.currentEntry ? (dropdownRoot.currentEntry.band + " · ch " + dropdownRoot.currentEntry.channel) : ""
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
          Item { Layout.fillWidth: true }
          Rectangle {
            implicitWidth: editLabel.implicitWidth + 10
            implicitHeight: 18
            radius: 2
            color: editMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
            Text { id: editLabel; anchors.centerIn: parent; text: "[e]dit"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            MouseArea { id: editMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.openEdit(dropdownRoot.currentEntry, "edit") }
          }
          Rectangle {
            implicitWidth: discLabel.implicitWidth + 10
            implicitHeight: 18
            radius: 2
            color: discMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
            Text { id: discLabel; anchors.centerIn: parent; text: "[d]isconnect"; color: discMouse.containsMouse ? dropdownRoot.colors[1] : dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            MouseArea { id: discMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.disconnectCurrent() }
          }
        }

        Item {
          visible: dropdownRoot.currentEntry !== null
          width: parent.width
          height: 16
          Row {
            spacing: 4
            Text { text: "signal"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            Text {
              readonly property int n: dropdownRoot.currentEntry ? Math.round(dropdownRoot.currentEntry.sig / 10) : 0
              text: "█".repeat(n)
              color: dropdownRoot.currentEntry ? dropdownRoot.sigColor(dropdownRoot.currentEntry.sig) : dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              readonly property int n: dropdownRoot.currentEntry ? Math.round(dropdownRoot.currentEntry.sig / 10) : 0
              text: "░".repeat(10 - n)
              color: dropdownRoot.hoverColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text { text: (dropdownRoot.currentEntry ? dropdownRoot.currentEntry.sig : 0) + "%"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          }
        }

        RowLayout {
          visible: dropdownRoot.currentEntry !== null
          width: parent.width
          spacing: 24
          Column {
            spacing: 1
            Repeater {
              model: [
                { k: "security", v: dropdownRoot.currentEntry ? dropdownRoot.currentEntry.sec : "" },
                { k: "gateway", v: dropdownRoot.ifaceDetails.gateway || "—" },
                { k: "uptime", v: dropdownRoot.uptimeText },
              ]
              delegate: RowLayout {
                required property var modelData
                spacing: 6
                Text { text: modelData.k; Layout.preferredWidth: 64; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                Text { text: modelData.v; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              }
            }
          }
          Column {
            spacing: 1
            Repeater {
              model: [
                { k: "dns", v: (dropdownRoot.ifaceDetails.dns && dropdownRoot.ifaceDetails.dns.length > 0) ? dropdownRoot.ifaceDetails.dns[0] : "—" },
                { k: "mac", v: dropdownRoot.ifaceDetails.mac || "—" },
                { k: "speed", v: "↓" + dropdownRoot.formatRate(dropdownRoot.rxRate) + " ↑" + dropdownRoot.formatRate(dropdownRoot.txRate) },
              ]
              delegate: RowLayout {
                required property var modelData
                spacing: 6
                Text { text: modelData.k; Layout.preferredWidth: 40; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                Text { text: modelData.v; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              }
            }
          }
        }

        Text {
          visible: dropdownRoot.currentEntry === null
          text: "○ not connected — pick a network below"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }

        Text {
          visible: dropdownRoot.netError.length > 0
          width: parent.width
          wrapMode: Text.WordWrap
          text: dropdownRoot.netError
          color: dropdownRoot.colors[1]
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }
      }

      Section {
        width: parent.width
        label: "available (" + dropdownRoot.availableNetworks.length + ")"
        labelColor: dropdownRoot.colors[0]
        paddingTop: 10
        paddingBottom: 6
        paddingSide: 4
        spacing: 2

        rightContent: Text {
          text: dropdownRoot.scanning ? "scanning…" : "[r]escan"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }

        Repeater {
          model: dropdownRoot.availableNetworks
          delegate: Rectangle {
            id: netRow
            required property var modelData
            required property int index
            readonly property bool sel: dropdownRoot.view === "main" && dropdownRoot.section === "networks" && index === dropdownRoot.sel

            width: parent.width
            height: 22
            radius: 2
            color: sel ? "#2f343e" : (netMouse.containsMouse ? "#2f343e" : "transparent")

            MouseArea {
              id: netMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: dropdownRoot.sel = netRow.index
              onDoubleClicked: dropdownRoot.connect(netRow.modelData)
            }

            Text {
              id: netMarker
              x: 8
              width: 10
              anchors.verticalCenter: parent.verticalCenter
              text: netRow.sel ? "▌" : (netRow.modelData.connecting ? "…" : "")
              color: dropdownRoot.colors[0]
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }

            Rectangle {
              id: netActions
              visible: netRow.sel || netRow.modelData.known
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: netActionsRow.implicitWidth
              implicitHeight: 18
              color: "transparent"
              Row {
                id: netActionsRow
                spacing: 2
                Rectangle {
                  visible: netRow.sel
                  implicitWidth: connLabel.implicitWidth + 8
                  implicitHeight: 18
                  radius: 2
                  color: connMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
                  Text { id: connLabel; anchors.centerIn: parent; text: "[⏎]"; color: dropdownRoot.colors[3]; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                  MouseArea { id: connMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.connect(netRow.modelData) }
                }
                Rectangle {
                  visible: netRow.sel
                  implicitWidth: editRowLabel.implicitWidth + 8
                  implicitHeight: 18
                  radius: 2
                  color: editRowMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
                  Text { id: editRowLabel; anchors.centerIn: parent; text: "[e]"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                  MouseArea { id: editRowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.openEdit(netRow.modelData, "connect") }
                }
                Text {
                  visible: !netRow.sel && netRow.modelData.known
                  text: "saved"
                  color: dropdownRoot.mutedColor
                  font.family: "JetBrains Mono"
                  font.pixelSize: 12
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
            Text {
              id: netBand
              anchors.right: netActions.visible ? netActions.left : parent.right
              anchors.rightMargin: netActions.visible ? 10 : 8
              anchors.verticalCenter: parent.verticalCenter
              text: netRow.modelData.band
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              id: netSec
              anchors.right: netBand.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: netRow.modelData.sec
              color: netRow.modelData.sec === "open" ? dropdownRoot.colors[1] : dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              id: netSig
              anchors.right: netSec.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: dropdownRoot.bars(netRow.modelData.sig).strong + dropdownRoot.bars(netRow.modelData.sig).weak
              font.family: "JetBrains Mono"
              font.pixelSize: 13
              color: dropdownRoot.hoverColor
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: dropdownRoot.bars(netRow.modelData.sig).strong
                color: dropdownRoot.sigColor(netRow.modelData.sig)
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
            }
            Text {
              x: netMarker.x + netMarker.width + 6
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, netSig.x - x - 10)
              elide: Text.ElideRight
              text: netRow.modelData.ssid
              color: dropdownRoot.fgColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
        }

        Text {
          visible: dropdownRoot.availableNetworks.length === 0
          x: 8
          text: dropdownRoot.scanning ? "scanning…" : "nothing found -- [r]escan"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      // ----- VPN: GlobalProtect + Tailscale, see header comment -----
      Section {
        width: parent.width
        label: "vpn"
        labelColor: dropdownRoot.colors[4]
        paddingTop: 10
        paddingBottom: 6
        paddingSide: 8
        spacing: 6

        Rectangle {
          width: parent.width
          implicitHeight: gpRow.implicitHeight + 4
          radius: 2
          color: (dropdownRoot.section === "vpn" && dropdownRoot.vpnSel === 0) ? "#2f343e" : "transparent"
          RowLayout {
            id: gpRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: (dropdownRoot.gpStatus === "connected" || dropdownRoot.gpStatus === "connected-internal") ? "[x]" : "[ ]"
              color: (dropdownRoot.gpStatus === "connected" || dropdownRoot.gpStatus === "connected-internal") ? dropdownRoot.colors[4] : dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text { text: "LUC (GlobalProtect)"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13; Layout.leftMargin: 6 }
            Item { Layout.fillWidth: true }
            Text {
              text: dropdownRoot.gpBusy ? "…" : dropdownRoot.gpStatus === "connected-internal" ? "up · internal" : dropdownRoot.gpStatus === "connected" ? "up" : dropdownRoot.gpStatus
              color: dropdownRoot.gpStatus.startsWith("connected") ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.gpToggle() }
        }
        RowLayout {
          visible: dropdownRoot.gpMfaPrompt.length > 0
          width: parent.width
          spacing: 8
          Text { text: dropdownRoot.gpMfaPrompt + ":"; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          Rectangle {
            Layout.preferredWidth: 100
            implicitHeight: 20
            color: "#1e2127"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: mfaInput.activeFocus ? dropdownRoot.colors[2] : dropdownRoot.hoverColor }
            TextInput {
              id: mfaInput
              anchors.fill: parent
              anchors.margins: 4
              color: dropdownRoot.fgColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
              focus: true
              text: dropdownRoot.gpMfaInput
              onTextEdited: dropdownRoot.gpMfaInput = text
              onAccepted: dropdownRoot.gpSubmitMfa()
            }
          }
        }

        Rectangle {
          width: parent.width
          implicitHeight: tsRow.implicitHeight + 4
          radius: 2
          color: (dropdownRoot.section === "vpn" && dropdownRoot.vpnSel === 1) ? "#2f343e" : "transparent"
          RowLayout {
            id: tsRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: dropdownRoot.tsStatus === "Running" ? "[x]" : "[ ]"
              color: dropdownRoot.tsStatus === "Running" ? dropdownRoot.colors[4] : dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text { text: "Tailscale"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13; Layout.leftMargin: 6 }
            Item { Layout.fillWidth: true }
            Text {
              text: dropdownRoot.tsBusy ? "…" : dropdownRoot.tsStatus === "Running" ? ("up · " + (dropdownRoot.tsIps[0] || "")) : "down"
              color: dropdownRoot.tsStatus === "Running" ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.tsToggle() }
        }
      }
    }

    // ===== EDIT VIEW =====
    Column {
      visible: dropdownRoot.view === "edit" && dropdownRoot.draft !== null
      width: parent.width

      Item { width: 1; height: 8 }

      Rectangle {
        width: parent.width
        height: editCol.implicitHeight + 28
        radius: 2
        color: "transparent"
        border.width: 1
        border.color: dropdownRoot.hoverColor

        Text {
          x: 8
          y: -9
          leftPadding: 6
          rightPadding: 6
          text: dropdownRoot.draft ? (dropdownRoot.draft.mode === "connect" ? "connect ─ " + dropdownRoot.draft.ssid : "edit ─ " + dropdownRoot.draft.ssid) : ""
          color: dropdownRoot.colors[2]
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
        }

        ColumnLayout {
          id: editCol
          x: 14
          y: 14
          width: parent.width - 28
          spacing: 6

          FormField {
            label: "ssid"
            mode: "text"
            fieldEnabled: false
            value: dropdownRoot.draft ? dropdownRoot.draft.ssid : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            accentColor: dropdownRoot.colors[0]
          }
          FormField {
            // Cycle-mode for visual consistency with ipv4/mac address
            // below, even though it's still disabled -- an AP's security
            // type isn't something you choose when connecting to a
            // network that's already been scanned, it's just reporting
            // what's actually there.
            label: "security"
            mode: "cycle"
            fieldEnabled: false
            value: dropdownRoot.draft ? dropdownRoot.draft.sec : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
          }
          FormField {
            visible: dropdownRoot.draft && dropdownRoot.draft.sec !== "open"
            label: "password"
            mode: dropdownRoot.draft && dropdownRoot.draft.show ? "text" : "password"
            value: dropdownRoot.draft ? dropdownRoot.draft.pass : ""
            placeholder: dropdownRoot.draft && dropdownRoot.draft.mode === "edit" ? "leave blank to keep current password" : ""
            showToggle: true
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            accentColor: dropdownRoot.colors[0]
            onValueEdited: (v) => dropdownRoot.setDraft({ pass: v })
            onAccepted: dropdownRoot.saveDraft()
            onToggleVisibility: dropdownRoot.setDraft({ show: !dropdownRoot.draft.show })
          }

          Text {
            visible: dropdownRoot.draft && dropdownRoot.draft.mode === "connect"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "ip/mac settings become editable after connecting for the first time -- nmcli has no profile to write them to yet"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }
          FormField {
            label: "ipv4"
            mode: "cycle"
            fieldEnabled: dropdownRoot.draft && dropdownRoot.draft.mode === "edit"
            value: dropdownRoot.draft ? dropdownRoot.draft.ipMode : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            onCycled: dropdownRoot.setDraft({ ipMode: dropdownRoot.cyc(["Automatic (DHCP)", "Manual"], dropdownRoot.draft.ipMode) })
          }
          FormField {
            visible: dropdownRoot.draft && dropdownRoot.draft.mode === "edit" && dropdownRoot.draft.ipMode === "Manual"
            label: "address"
            mode: "text"
            placeholder: "192.168.1.50/24"
            value: dropdownRoot.draft ? dropdownRoot.draft.addr : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            accentColor: dropdownRoot.colors[0]
            onValueEdited: (v) => dropdownRoot.setDraft({ addr: v })
            onAccepted: dropdownRoot.saveDraft()
          }
          FormField {
            visible: dropdownRoot.draft && dropdownRoot.draft.mode === "edit" && dropdownRoot.draft.ipMode === "Manual"
            label: "gateway"
            mode: "text"
            placeholder: "192.168.1.1"
            value: dropdownRoot.draft ? dropdownRoot.draft.gw : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            accentColor: dropdownRoot.colors[0]
            onValueEdited: (v) => dropdownRoot.setDraft({ gw: v })
            onAccepted: dropdownRoot.saveDraft()
          }
          FormField {
            visible: dropdownRoot.draft && dropdownRoot.draft.mode === "edit" && dropdownRoot.draft.ipMode === "Manual"
            label: "dns"
            mode: "text"
            placeholder: "8.8.8.8 8.8.4.4"
            value: dropdownRoot.draft ? dropdownRoot.draft.dns : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            accentColor: dropdownRoot.colors[0]
            onValueEdited: (v) => dropdownRoot.setDraft({ dns: v })
            onAccepted: dropdownRoot.saveDraft()
          }
          FormField {
            label: "mac address"
            mode: "cycle"
            fieldEnabled: dropdownRoot.draft && dropdownRoot.draft.mode === "edit"
            value: dropdownRoot.draft ? dropdownRoot.draft.mac : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            onCycled: dropdownRoot.setDraft({ mac: dropdownRoot.cyc(["Stable", "Random"], dropdownRoot.draft.mac) })
          }

          Item {
            implicitWidth: autoRow.implicitWidth
            implicitHeight: autoRow.implicitHeight
            Row {
              id: autoRow
              spacing: 6
              Text { text: dropdownRoot.draft && dropdownRoot.draft.auto ? "[x]" : "[ ]"; color: dropdownRoot.draft && dropdownRoot.draft.auto ? dropdownRoot.colors[0] : dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              Text { text: "autoconnect"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.setDraft({ auto: !dropdownRoot.draft.auto }) }
          }

          Row {
            spacing: 8
            Rectangle {
              implicitWidth: saveLabel.implicitWidth + 20
              implicitHeight: 22
              radius: 2
              color: dropdownRoot.colors[0]
              Text { id: saveLabel; anchors.centerIn: parent; text: dropdownRoot.draft && dropdownRoot.draft.mode === "connect" ? "< connect >" : "< save >"; color: "#282c34"; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.saveDraft() }
            }
            Rectangle {
              implicitWidth: cancelLabel.implicitWidth + 20
              implicitHeight: 22
              radius: 2
              color: cancelMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text { id: cancelLabel; anchors.centerIn: parent; text: "< cancel >"; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.backMain() }
            }
            Rectangle {
              visible: dropdownRoot.draft && dropdownRoot.draft.entry && dropdownRoot.draft.entry.known
              implicitWidth: forgetLabel.implicitWidth + 20
              implicitHeight: 22
              radius: 2
              color: forgetMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text { id: forgetLabel; anchors.centerIn: parent; text: "< forget >"; color: dropdownRoot.colors[1]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              MouseArea { id: forgetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.forgetDraft() }
            }
          }
        }
      }
    }

    // ===== HOTSPOT VIEW =====
    Column {
      visible: dropdownRoot.view === "hotspot"
      width: parent.width
      spacing: 16

      Item { width: 1; height: 8 }

      Rectangle {
        width: parent.width
        height: hsCol.implicitHeight + 28
        radius: 2
        color: "transparent"
        border.width: 1
        border.color: dropdownRoot.hoverColor

        Text {
          x: 8
          y: -9
          leftPadding: 6
          rightPadding: 6
          text: "hotspot"
          color: "#d19a66"
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
        }
        Item {
          // Row doesn't allow anchored children (it positions them via
          // x/y itself), unlike the "hotspot" Text label above --
          // that's why the background-masking rectangle here is a
          // sibling of the Row inside its own Item wrapper, rather than
          // a child of the Row the way Section.qml's labelText does it.
          anchors.right: parent.right
          anchors.rightMargin: 8
          y: -9
          implicitWidth: hsStatusRow.implicitWidth + 12
          implicitHeight: hsStatusRow.implicitHeight
          Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
          Row {
            id: hsStatusRow
            anchors.centerIn: parent
            spacing: 4
            Text {
              visible: dropdownRoot.hsOn && !dropdownRoot.hs.busy
              text: Phosphor.icon("broadcast")
              color: dropdownRoot.colors[3]
              font.family: "Phosphor"
              font.pixelSize: 13
            }
            Text {
              text: dropdownRoot.hs.busy ? "…" : dropdownRoot.hsOn ? "broadcasting" : "○ off"
              color: dropdownRoot.hsOn ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
        }

        ColumnLayout {
          id: hsCol
          x: 14
          y: 14
          width: parent.width - 28
          spacing: 6

          FormField {
            label: "name"
            mode: "text"
            value: dropdownRoot.hs.ssid
            fieldEnabled: !dropdownRoot.hsOn
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            accentColor: "#d19a66"
            onValueEdited: (v) => dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { ssid: v })
          }
          FormField {
            label: "password"
            mode: dropdownRoot.hs.show ? "text" : "password"
            value: dropdownRoot.hs.pass
            fieldEnabled: !dropdownRoot.hsOn
            showToggle: true
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            accentColor: "#d19a66"
            onValueEdited: (v) => dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { pass: v })
            onToggleVisibility: dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { show: !dropdownRoot.hs.show })
          }
          FormField {
            label: "band"
            mode: "cycle"
            value: dropdownRoot.hs.band
            fieldEnabled: !dropdownRoot.hsOn
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            onCycled: dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { band: dropdownRoot.cyc(["2.4 GHz", "5 GHz"], dropdownRoot.hs.band) })
          }
          Item {
            implicitWidth: hiddenRow.implicitWidth
            implicitHeight: hiddenRow.implicitHeight
            Row {
              id: hiddenRow
              spacing: 6
              Text { text: dropdownRoot.hs.hidden ? "[x]" : "[ ]"; color: dropdownRoot.hs.hidden ? "#d19a66" : dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              Text { text: "hidden network"; color: dropdownRoot.hsOn ? dropdownRoot.mutedColor : dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            }
            MouseArea {
              anchors.fill: parent
              enabled: !dropdownRoot.hsOn
              cursorShape: Qt.PointingHandCursor
              onClicked: dropdownRoot.hs = Object.assign({}, dropdownRoot.hs, { hidden: !dropdownRoot.hs.hidden })
            }
          }
          // Not a real nmcli hotspot setting -- NetworkManager NATs
          // clients through whichever connection is currently providing
          // the default route automatically, there's no "share from a
          // specific interface" flag to set. This just reports what
          // that upstream actually is instead of pretending it's a
          // choice.
          RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Text { text: "share from"; Layout.preferredWidth: 130; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            Text {
              text: dropdownRoot.hsShareIface.length > 0 ? dropdownRoot.hsShareIface + " · ethernet (auto)" : "no wired uplink detected"
              color: dropdownRoot.hsShareIface.length > 0 ? dropdownRoot.fgColor : dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
              implicitWidth: hsBtnLabel.implicitWidth + 20
              implicitHeight: 22
              radius: 2
              opacity: dropdownRoot.hs.busy ? 0.6 : 1
              color: dropdownRoot.hsOn ? dropdownRoot.colors[1] : "#d19a66"
              Text {
                id: hsBtnLabel
                anchors.centerIn: parent
                text: dropdownRoot.hs.busy ? "< …working >" : dropdownRoot.hsOn ? "< stop hotspot >" : "< start hotspot >"
                color: "#282c34"
                font.family: "JetBrains Mono"
                font.weight: Font.DemiBold
                font.pixelSize: 13
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.toggleHotspot() }
            }
            Text {
              text: dropdownRoot.hsOn ? "broadcasting on " + dropdownRoot.ifaceName : "wi-fi will disconnect while active"
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
          Text {
            visible: dropdownRoot.hs.error.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: dropdownRoot.hs.error
            color: dropdownRoot.colors[1]
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }

          Text {
            visible: dropdownRoot.hsOn
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: "connected devices (" + dropdownRoot.hsClientRows.length + ")"
            color: dropdownRoot.colors[0]
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          ColumnLayout {
            visible: dropdownRoot.hsOn
            Layout.fillWidth: true
            spacing: 3
            Repeater {
              model: dropdownRoot.hsClientRows
              delegate: Item {
                id: clientRow
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 18

                Text {
                  id: clientDot
                  anchors.verticalCenter: parent.verticalCenter
                  text: clientRow.modelData.online ? "●" : "○"
                  color: clientRow.modelData.online ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
                  font.family: "JetBrains Mono"
                  font.pixelSize: 13
                }
                Text {
                  id: clientMac
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: clientRow.modelData.mac
                  color: dropdownRoot.mutedColor
                  font.family: "JetBrains Mono"
                  font.pixelSize: 12
                }
                Text {
                  id: clientIp
                  anchors.right: clientMac.left
                  anchors.rightMargin: 14
                  anchors.verticalCenter: parent.verticalCenter
                  text: clientRow.modelData.ip
                  color: dropdownRoot.mutedColor
                  font.family: "JetBrains Mono"
                  font.pixelSize: 13
                }
                Text {
                  anchors.left: clientDot.right
                  anchors.leftMargin: 6
                  anchors.right: clientIp.left
                  anchors.rightMargin: 14
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: clientRow.modelData.name
                  color: dropdownRoot.fgColor
                  font.family: "JetBrains Mono"
                  font.pixelSize: 13
                }
              }
            }
            Text {
              visible: dropdownRoot.hsClientRows.length === 0
              text: "no devices connected yet"
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
        }
      }
    }

    Item { width: 1; height: 12 }

    // ----- hints -----
    Flow {
      width: parent.width
      spacing: 14
      readonly property var hints: dropdownRoot.view === "main"
        ? (dropdownRoot.section === "networks"
          ? [{ k: "tab", l: "vpn ↔ networks" }, { k: "j/k", l: "move" }, { k: "⏎", l: "connect" }, { k: "e", l: "edit" }, { k: "d", l: "disconnect" }, { k: "r", l: "rescan" }, { k: "esc", l: "close" }]
          : [{ k: "tab", l: "vpn ↔ networks" }, { k: "j/k", l: "move" }, { k: "⏎/space", l: "toggle" }, { k: "esc", l: "close" }])
        : dropdownRoot.view === "edit"
          ? [{ k: "⏎", l: "save" }, { k: "esc", l: "cancel" }]
          : [{ k: "space", l: dropdownRoot.hsOn ? "stop" : "start" }, { k: "1", l: "wifi" }, { k: "esc", l: "back" }]
      Repeater {
        model: parent.hints
        RowLayout {
          required property var modelData
          spacing: 4
          Text { text: modelData.k; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          Text { text: modelData.l; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        }
      }
    }
  }
}

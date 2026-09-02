import Quickshell.Networking

// ===== NETWORK =====
// Ported from home/waybar.nix's network module -- same 5-step wifi signal
// icon array, same ethernet/disconnected glyphs, same inline essid label
// (waybar's format-wifi was "{icon}    {essid} ", shown right in the bar,
// not just the tooltip -- so the label here isn't new, it's matching what
// waybar actually displayed). signalStrength is a 0..1 fraction, confirmed
// live against this laptop's real "LUC" connection (0.57), not assumed.
//
// Each glyph carries its own size (see Bluetooth.qml for why -- MDI icons
// aren't uniformly sized at the same pixel size). All start at the same
// 20px baseline here since there's no live-eyeballed evidence yet that any
// specific one of these needs adjusting the way bluetooth's did -- but
// each is independently tunable now, so if one of the signal-strength
// steps or ethernet/disconnected looks off once you actually see it,
// nudge just that entry's `size` rather than the whole button's.
Button {
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
  readonly property var activeWifiNetwork: {
    if (!wifiDevice || !wifiDevice.networks) return null;
    for (const net of wifiDevice.networks.values) {
      if (net.connected) return net;
    }
    return null;
  }
  readonly property var wifiIcons: [
    { icon: "󰤯", size: 20 },
    { icon: "󰤟", size: 20 },
    { icon: "󰤢", size: 20 },
    { icon: "󰤥", size: 20 },
    { icon: "󰤨", size: 20 }
  ]
  // Parens required -- `property var x: { ... }` with the object literal
  // right after the colon parses as a block statement (like the multi-line
  // properties above), not an object literal; QML/JS needs the
  // parenthesized form to disambiguate a single-expression object literal
  // here. Not an issue inside the wifiIcons array above (element position,
  // no ambiguity) or state's `return { ... }` below (return-expression
  // position, same reason).
  readonly property var ethernetIcon: ({ icon: "󰀂", size: 20 })
  readonly property var disconnectedIcon: ({ icon: "󰤮", size: 20 })

  readonly property var state: {
    if (activeWifiNetwork) {
      const idx = Math.min(wifiIcons.length - 1, Math.max(0, Math.floor(activeWifiNetwork.signalStrength * wifiIcons.length)));
      return wifiIcons[idx];
    }
    if (wiredDevice && wiredDevice.connected) return ethernetIcon;
    return disconnectedIcon;
  }

  icon: state.icon
  iconSize: state.size
  label: activeWifiNetwork ? activeWifiNetwork.name : ""
  command: [ "ghostty", "--class=com.joelsgc.floating", "-e", "netpala" ]
}

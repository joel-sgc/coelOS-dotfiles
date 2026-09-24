import Quickshell.Networking
import "./Phosphor.js" as Phosphor

// ===== NETWORK =====
// Bar icon still reflects the real wifi/wired device (Quickshell.
// Networking) -- 3-step wifi signal icon (Phosphor only has low/medium/
// high), same ethernet/disconnected distinction, same inline essid label
// (waybar's format-wifi was "{icon}    {essid} ", shown right in the bar,
// not just the tooltip). signalStrength is a 0..1 fraction, confirmed
// live against this laptop's real "LUC" connection (0.57), not assumed.
//
// Only the dropdown this opens (NetworkDropdown.qml) is hardcoded for
// now -- same split as Bluetooth.qml/PowerDropdown.qml between real
// bar-button state and (for now, on this one) placeholder dropdown
// content.
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
    Phosphor.icon("wifi-low"),
    Phosphor.icon("wifi-medium"),
    Phosphor.icon("wifi-high")
  ]

  // Not "state" -- Item already has a built-in `state` (QtQuick's States
  // system), and redeclaring it collides rather than overrides.
  readonly property var iconState: {
    if (activeWifiNetwork) {
      const idx = Math.min(wifiIcons.length - 1, Math.max(0, Math.floor(activeWifiNetwork.signalStrength * wifiIcons.length)));
      return wifiIcons[idx];
    }
    if (wiredDevice && wiredDevice.connected) return Phosphor.icon("network");
    return Phosphor.icon("wifi-slash");
  }

  icon: iconState
  label: activeWifiNetwork ? activeWifiNetwork.name : ""
  // Elides rather than pushing the rest of the bar around -- matches the
  // mock's max-width:110px on the essid label.
  // labelMaxWidth: 110
  active: root.openPopup === "network"
  onClicked: root.openPopup = root.openPopup === "network" ? "" : "network"
}

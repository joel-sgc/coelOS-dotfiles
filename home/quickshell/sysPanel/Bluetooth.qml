import Quickshell.Bluetooth
import "./Phosphor.js" as Phosphor

// ===== BLUETOOTH =====
// Ported from home/waybar.nix's bluetooth module -- same icon states (no
// controller and off/disabled all share one icon there too, so they
// collapse the same way here). No device-count tooltip -- that lived in
// waybar's tooltip, a real popup widget, out of scope here; the bar icon
// itself was always state-only, which is what this matches.
Button {
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property int connectedCount: {
    let n = 0;
    for (const d of Bluetooth.devices.values) {
      if (d.connected) n++;
    }
    return n;
  }

  // Not "state" -- Item already has a built-in `state` (QtQuick's States
  // system), and redeclaring it collides rather than overrides.
  readonly property var iconState: {
    if (!adapter || !adapter.enabled) return Phosphor.icon("bluetooth-slash");
    if (connectedCount > 0) return Phosphor.icon("bluetooth-connected");
    return Phosphor.icon("bluetooth");
  }

  icon: iconState
  command: [ "ghostty", "--class=com.joelsgc.floating", "-e", "bluepala" ]
}

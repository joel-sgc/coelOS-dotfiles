import Quickshell.Bluetooth
import "./Phosphor.js" as Phosphor

// ===== BLUETOOTH =====
// Bar icon still reflects the real adapter (Quickshell.Bluetooth) -- only
// the dropdown this opens (BluetoothDropdown.qml) is hardcoded for now,
// same split PowerDropdown.qml already has between real bar-button state
// and (for now, on this one) placeholder dropdown content.
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
  active: root.openPopup === "bluetooth"
  onClicked: root.openPopup = root.openPopup === "bluetooth" ? "" : "bluetooth"
}

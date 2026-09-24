import Quickshell.Services.UPower
import "./Phosphor.js" as Phosphor

// ===== BATTERY =====
// Percentage/state come from Quickshell's own UPower service (real DBus
// data) -- `device.percentage` is a 0..1 fraction, confirmed live against
// this laptop's actual battery (BAT1) rather than assumed. Only two icons
// (charging/not) rather than a full per-decile charge/discharge icon
// array -- static glyph + live percentage text is enough for now.
//
// Opens PowerDropdown (see Panel.qml) instead of launching
// coel-power-profiles-menu -- phase 2 of the panel redesign replaces that
// rofi menu with a real inline dropdown covering the same ground
// (profile switching) plus battery detail, brightness and session
// actions it didn't have.
Button {
  readonly property var device: UPower.displayDevice
  readonly property bool charging: device.ready && device.state === UPowerDeviceState.Charging
  readonly property int pct: device.ready ? Math.round(device.percentage * 100) : 0

  visible: device.ready && device.isLaptopBattery
  icon: charging ? Phosphor.icon("battery-charging") : Phosphor.icon("battery-full")
  iconSize: 15
  label: pct + "%"
  active: root.openPopup === "power"
  onClicked: root.openPopup = root.openPopup === "power" ? "" : "power"
}

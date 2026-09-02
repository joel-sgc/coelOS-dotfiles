import Quickshell.Services.UPower

// ===== BATTERY =====
// Ported from home/waybar.nix's battery module -- same on-click
// (coel-power-profiles-menu). Percentage/state come from Quickshell's own
// UPower service (real DBus data, not a polled script like Cpu.qml needs)
// -- `device.percentage` is a 0..1 fraction, confirmed live against this
// laptop's actual battery (BAT1) rather than assumed. Only two icons
// (charging/not) rather than waybar's full per-decile charge/discharge
// icon arrays -- static glyph + live percentage text is enough for now.
Button {
  readonly property var device: UPower.displayDevice
  readonly property bool charging: device.ready && device.state === UPowerDeviceState.Charging
  readonly property int pct: device.ready ? Math.round(device.percentage * 100) : 0

  visible: device.ready && device.isLaptopBattery
  icon: charging ? "󰂄" : "󰁹"
  label: pct + "%"
  command: [ "coel-power-profiles-menu" ]
}

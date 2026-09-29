import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../sysPanel/Phosphor.js" as Phosphor

// ===== NETWORK + BATTERY =====
// Top-right chips in the "1a Corner" mockup. Wifi SSID is still static
// demo data (no real NetworkManager wiring yet -- deferred, and hidden
// entirely in login mode anyway since the greeter has no network before
// login). Battery is real: same Quickshell.Services.UPower pattern
// sysPanel/buttons/Battery.qml already uses against this laptop's actual
// battery, self-contained here rather than threaded through Lock.qml/
// Greeter.qml/LockScreen.qml as a prop, since it's system-wide state
// available to any user (including the greeter's anonymous session), not
// something that needs to come from a particular session's backend.
RowLayout {
  id: root

  property color fgColor: "#7f848e"
  property string ssid: "home-5g"
  property bool showNetwork: true

  readonly property var device: UPower.displayDevice
  readonly property bool batteryCharging: device.ready && device.state === UPowerDeviceState.Charging
  readonly property int batteryPct: device.ready ? Math.round(device.percentage * 100) : 0
  readonly property bool hasBattery: device.ready && device.isLaptopBattery

  spacing: 18

  RowLayout {
    visible: root.showNetwork
    spacing: 6
    Text {
      text: Phosphor.icon("wifi-high")
      color: root.fgColor
      font.family: "Phosphor"
      font.pixelSize: 15
    }
    Text {
      text: root.ssid
      color: root.fgColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
    }
  }

  RowLayout {
    visible: root.hasBattery
    spacing: 6
    Text {
      text: root.batteryCharging ? Phosphor.icon("battery-charging") : Phosphor.icon("battery-high")
      color: root.fgColor
      font.family: "Phosphor"
      font.pixelSize: 16
    }
    Text {
      text: root.batteryPct + "%"
      color: root.fgColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
    }
  }
}

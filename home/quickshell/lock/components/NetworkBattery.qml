import QtQuick
import QtQuick.Layouts
import "../../sysPanel/Phosphor.js" as Phosphor

// ===== NETWORK + BATTERY =====
// Top-right chips in the "1a Corner" mockup. Static demo props this pass
// (no real NetworkManager/UPower wiring yet -- that's real backend work,
// explicitly deferred per the lock-screen plan) -- see
// sysPanel/dropdowns/NetworkDropdown.qml / PowerDropdown.qml for where the
// real data would eventually come from.
RowLayout {
  id: root

  property color fgColor: "#7f848e"
  property string ssid: "home-5g"
  property int batteryPct: 82

  spacing: 18

  RowLayout {
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
    spacing: 6
    Text {
      text: Phosphor.icon("battery-high")
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

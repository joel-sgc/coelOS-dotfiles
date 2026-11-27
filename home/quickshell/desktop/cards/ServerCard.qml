import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import ".."
import "../data"

// Home server: C compact (cpu / ram / disk bars), M minimized. Key: r refresh.
CardFrame {
  id: card
  property string size: "C"
  property string flavor: ""
  readonly property var sd: ServerData

  title: "server"
  sub: sd.name
  dot: sd.failed ? Pal.red : sd.loaded ? (sd.healthy ? Pal.green : Pal.yellow) : Pal.muted
  summary: sd.loaded ? sd.state + " · cpu " + sd.cpuPct + "%" : sd.state
  minimized: size === "M"

  function handleKey(e) {
    if (e.key === Qt.Key_R) { sd.refresh(); return true; }
    return false;
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: 6
    Repeater {
      model: [
        { label: "cpu", icon: "cpu", color: Pal.blue, key: "cpuPct" },
        { label: "ram", icon: "memory", color: Pal.purple, key: "ramPct" },
        { label: "disk", icon: "hard-drives", color: Pal.green, key: "diskPct" },
      ]
      RowLayout {
        required property var modelData
        readonly property int v: card.sd.loaded ? card.sd[modelData.key] : 0
        Layout.fillWidth: true
        spacing: 6
        PhIcon { Layout.preferredWidth: 16; name: parent.modelData.icon; color: parent.modelData.color; font.pixelSize: 13 }
        Mono { Layout.preferredWidth: 36; text: parent.modelData.label; color: Pal.muted }
        TBar { Layout.fillWidth: true; value: parent.v; fill: parent.v >= 90 ? Pal.red : parent.v >= 70 ? Pal.yellow : parent.modelData.color }
        Mono { Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight; text: card.sd.loaded ? parent.v + "%" : "--" }
      }
    }
  }
  Mono {
    Layout.fillWidth: true
    Layout.topMargin: 8
    text: card.sd.loaded ? "up " + card.sd.uptimeText + " · load " + card.sd.load + " · " + card.sd.state : card.sd.state
    color: Pal.muted
    elide: Text.ElideRight
  }
}

import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import "../../island"
import "../../services"
import ".."

// The phone over KDE Connect (Desktop Board `phone`): S small (battery, the
// newest notification, ring / send file), M minimized. Data: services/Phone.
CardFrame {
  id: card
  property string size: "S"
  property string flavor: ""
  readonly property var ph: Phone

  title: "phone"
  sub: ph.name.toLowerCase()
  dot: ph.reachable ? Pal.green : Pal.muted
  minimized: size === "M"
  summary: ph.summary

  function handleKey(e) {
    if (e.text === "r") { ph.ring(); return true; }
    if (e.text === "s") { ph.sendFile(); return true; }
    return false;
  }

  readonly property color battColor: ph.battery < 0 ? Pal.muted : ph.battery <= 15 ? Pal.red : ph.battery <= 30 ? Pal.orange : Pal.green

  RowLayout {
    Layout.fillWidth: true
    spacing: 6
    PhIcon { Layout.preferredWidth: 16; name: "device-mobile"; color: Pal.fg; font.pixelSize: 14 }
    Mono { Layout.preferredWidth: 60; text: "battery"; color: Pal.muted }
    TBar { Layout.fillWidth: true; value: Math.max(0, card.ph.battery); fill: card.battColor }
    Mono {
      Layout.preferredWidth: 52
      horizontalAlignment: Text.AlignRight
      text: card.ph.battery >= 0 ? (card.ph.charging ? "⚡" : "") + card.ph.battery + "%" : "--"
    }
  }
  Box {
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 12; padSide: 12; padBottom: 8
    legend: "last notification"
    RowLayout {
      Layout.fillWidth: true
      Mono {
        Layout.fillWidth: true
        text: !card.ph.reachable ? "not connected" : card.ph.notification ? (card.ph.notification.title || card.ph.notification.app) : "nothing new"
        color: card.ph.notification && card.ph.reachable ? Pal.blue : Pal.muted
        elide: Text.ElideRight
      }
      Mono { visible: !!card.ph.notification && card.ph.reachable; text: card.ph.ago; color: Pal.muted }
    }
    Mono {
      visible: !!card.ph.notification && card.ph.reachable
      Layout.fillWidth: true
      text: card.ph.notification ? (card.ph.notification.text || "") : ""
      elide: Text.ElideRight
    }
  }
  RowLayout {
    Layout.topMargin: 12
    spacing: 6
    IslandButton { enabled: card.ph.reachable; icon: "bell-ringing"; text: "ring my phone"; onClicked: card.ph.ring() }
    IslandButton { enabled: card.ph.reachable; icon: "paper-plane-tilt"; text: "send file"; onClicked: card.ph.sendFile() }
  }
}

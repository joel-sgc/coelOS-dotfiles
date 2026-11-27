import QtQuick
import QtQuick.Layouts
import "../../widgets"
import ".."

// The pill's music card (Pill Board `musicCard`): art, title, artist · album,
// the player, progress and controls on the active Mpris player.
Column {
  id: card
  property var source      // services/Music
  property var engine
  property var screen
  readonly property var mu: source

  width: 380
  spacing: 12

  Row {
    spacing: 14
    Rectangle {
      width: 64; height: 64
      radius: 8
      clip: true
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Pal.cyan }
        GradientStop { position: 1; color: Pal.purple }
      }
      Image { anchors.fill: parent; source: card.mu ? card.mu.artUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: card.width - 64 - 14
      spacing: 3
      Mono { width: parent.width; text: card.mu ? card.mu.title : ""; font.pixelSize: 15; font.weight: Font.Medium; elide: Text.ElideRight }
      Mono { width: parent.width; text: card.mu ? [card.mu.artist, card.mu.album].filter(s => s).join(" · ") : ""; color: Pal.muted; elide: Text.ElideRight }
      Mono { text: card.mu ? card.mu.source : ""; color: Pal.muted; font.pixelSize: 11 }
    }
  }
  RowLayout {
    width: card.width
    spacing: 10
    Mono { text: card.mu ? card.mu.fmt(card.mu.position) : ""; color: Pal.muted }
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: 4
      radius: 2
      color: Pal.faint
      Rectangle { width: parent.width * (card.mu ? card.mu.progress : 0); height: parent.height; radius: 2; color: Pal.green }
    }
    Mono { text: card.mu && card.mu.length > 0 ? card.mu.fmt(card.mu.length) : "--:--"; color: Pal.muted }
  }
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 26
    Repeater {
      model: [["skip-back", 18, "previous"], ["", 22, "toggle"], ["skip-forward", 18, "next"]]
      PhIcon {
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        name: modelData[0] || (card.mu && card.mu.playing ? "pause" : "play")
        fill: true
        font.pixelSize: modelData[1]
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: card.mu[parent.modelData[2]]() }
      }
    }
  }
}

import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import "../../island"
import "../../services"
import "../../island/Parts.js" as P
import ".."

// Now playing (Desktop Board `nowPlaying`): L hero (200 px art), S small, M
// minimized. Mpris via services/Music. Keys: space play/pause, h/l or n
// previous/next. The board's "up next" isn't here: Mpris doesn't expose a queue.
CardFrame {
  id: card
  property string size: "S"
  property string flavor: ""
  readonly property var mu: Music
  readonly property bool big: size === "L"

  title: "now playing"
  sub: mu.source
  tint: Pal.green
  minimized: size === "M"
  summary: mu.title ? mu.line + " · " + mu.fmt(mu.position) : "nothing playing"

  function handleKey(e) {
    if (e.key === Qt.Key_Space) { mu.toggle(); return true; }
    if (e.text === "l" || e.text === "n" || e.key === Qt.Key_Right) { mu.next(); return true; }
    if (e.text === "h" || e.key === Qt.Key_Left) { mu.previous(); return true; }
    return false;
  }

  rightData: [
    IslandPart { part: P.eq(card.mu.playing ? P.C.gr : P.C.mu, card.mu.playing) }
  ]

  // Album art, or the board's gradient stand-in.
  component Art: Item {
    property int px: 56
    property int r: 6
    Layout.preferredWidth: px
    Layout.preferredHeight: px
    Rectangle {
      anchors.fill: parent
      radius: Globals.eyeCandyOff ? 0 : parent.r
      visible: art.status !== Image.Ready
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Pal.cyan }
        GradientStop { position: 1; color: Pal.purple }
      }
    }
    Image {
      id: art
      anchors.fill: parent
      source: card.mu.artUrl
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: status === Image.Ready
    }
  }
  component Ctl: PhIcon {
    property var act
    fill: true
    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: parent.act() }
  }
  component Progress: RowLayout {
    Layout.fillWidth: true
    spacing: 10
    Mono { text: card.mu.fmt(card.mu.position); color: Pal.muted }
    TBar { Layout.fillWidth: true; implicitHeight: card.big ? 6 : 4; value: card.mu.progress * 100; fill: Pal.green }
    Mono { text: card.mu.length > 0 ? card.mu.fmt(card.mu.length) : "--:--"; color: Pal.muted }
  }

  // ----- small -----
  RowLayout {
    visible: !card.big
    Layout.fillWidth: true
    spacing: 12
    Art { px: 56; r: 6 }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0
      Mono { Layout.fillWidth: true; text: card.mu.title || "nothing playing"; font.pixelSize: 15; font.weight: Font.Medium; elide: Text.ElideRight }
      Mono { Layout.fillWidth: true; text: card.mu.artist; color: Pal.green; elide: Text.ElideRight }
    }
    Row {
      spacing: 12
      Ctl { name: "skip-back"; font.pixelSize: 15; act: () => card.mu.previous() }
      Ctl { name: card.mu.playing ? "pause" : "play"; font.pixelSize: 17; act: () => card.mu.toggle() }
      Ctl { name: "skip-forward"; font.pixelSize: 15; act: () => card.mu.next() }
    }
  }
  Progress { visible: !card.big; Layout.topMargin: 10 }

  // ----- large -----
  RowLayout {
    visible: card.big
    Layout.fillWidth: true
    spacing: 24
    Art { px: 200; r: 12 }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 6
      Mono { Layout.fillWidth: true; text: card.mu.title || "nothing playing"; font.pixelSize: 30; font.weight: Font.Medium; font.letterSpacing: -0.6; elide: Text.ElideRight }
      Mono { Layout.fillWidth: true; text: card.mu.artist; font.pixelSize: 16; color: Pal.green; elide: Text.ElideRight }
      Mono { Layout.fillWidth: true; visible: text !== ""; text: card.mu.album; color: Pal.muted; elide: Text.ElideRight }
      Progress { Layout.topMargin: 10 }
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 28
        Ctl { name: "skip-back"; font.pixelSize: 22; act: () => card.mu.previous() }
        Ctl { name: card.mu.playing ? "pause" : "play"; font.pixelSize: 28; act: () => card.mu.toggle() }
        Ctl { name: "skip-forward"; font.pixelSize: 22; act: () => card.mu.next() }
        Item { Layout.fillWidth: true }
        Mono { visible: card.mu.volumePct >= 0; text: "vol " + card.mu.volumePct + "%"; color: Pal.muted }
      }
    }
  }
}

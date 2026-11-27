import QtQuick
import QtQuick.Layouts
import "../.."
import "../../widgets"
import ".."
import "../data"

// Weather: R regular (now + next 8h), C compact (one row), M minimized.
// Keys: u units, r refresh.
CardFrame {
  id: card
  property string size: "C"
  property string flavor: ""
  readonly property var wd: WeatherData

  title: "weather"
  sub: wd.place || "locating"
  summary: wd.summary
  minimized: size === "M"

  function handleKey(e) {
    if (e.key === Qt.Key_U) { wd.fahrenheit = !wd.fahrenheit; return true; }
    if (e.key === Qt.Key_R) { wd.refresh(); return true; }
    return false;
  }

  rightData: [
    TextButton {
      visible: card.size === "R"
      onClicked: card.wd.fahrenheit = !card.wd.fahrenheit
      Mono { text: "u"; color: Pal.yellow }
      Mono { text: card.wd.unit; color: Pal.muted }
    }
  ]

  readonly property var now: wd.spec(wd.code, wd.isDay)

  // ----- compact -----
  ColumnLayout {
    visible: card.size !== "R"
    Layout.fillWidth: true
    spacing: 6
    RowLayout {
      Layout.fillWidth: true
      spacing: 12
      PhIcon { name: card.wd.loaded ? card.now.name : "cloud-slash"; fill: card.wd.loaded && card.now.fill; color: card.wd.loaded ? card.now.color : Pal.muted; font.pixelSize: 30 }
      RowLayout {
        spacing: 0
        Mono { text: card.wd.loaded ? card.wd.cv(card.wd.tempC) + "°" : "--"; font.pixelSize: 24; font.weight: Font.Medium }
        Mono { Layout.alignment: Qt.AlignTop; Layout.topMargin: 4; text: card.wd.fahrenheit ? "F" : "C"; font.pixelSize: 13; color: Pal.muted }
      }
      ColumnLayout {
        spacing: 0
        Mono { text: card.wd.loaded ? card.wd.label(card.wd.code) : (card.wd.failed ? "offline" : "loading…") }
        Mono { visible: card.wd.loaded; text: "feels " + card.wd.cv(card.wd.feelsC) + "°"; color: Pal.muted }
      }
      Item { Layout.fillWidth: true }
      ColumnLayout {
        visible: card.wd.loaded
        spacing: 0
        Row { Layout.alignment: Qt.AlignRight; spacing: 6; Mono { text: "↑"; color: Pal.red } Mono { text: card.wd.cv(card.wd.hiC) + "°" } }
        Row { Layout.alignment: Qt.AlignRight; spacing: 6; Mono { text: "↓"; color: Pal.blue } Mono { text: card.wd.cv(card.wd.loC) + "°" } }
      }
    }
    Mono {
      visible: card.wd.loaded
      Layout.fillWidth: true
      text: card.wd.rainText + " · sunset " + card.wd.sunset
      color: Pal.muted
      elide: Text.ElideRight
    }
  }

  // ----- regular -----
  Box {
    visible: card.size === "R"
    Layout.fillWidth: true
    padTop: 14; padSide: 12; padBottom: 10
    legend: "now"
    rightLegend: card.wd.updatedText
    rightColor: card.wd.refreshing ? Pal.yellow : Pal.muted

    RowLayout {
      Layout.fillWidth: true
      spacing: 14
      PhIcon { name: card.wd.loaded ? card.now.name : "cloud-slash"; fill: card.wd.loaded && card.now.fill; color: card.wd.loaded ? card.now.color : Pal.muted; font.pixelSize: 44 }
      ColumnLayout {
        spacing: 0
        RowLayout {
          spacing: 0
          Mono { text: card.wd.loaded ? card.wd.cv(card.wd.tempC) : "--"; font.pixelSize: 34; font.weight: Font.Medium; font.letterSpacing: -0.7 }
          Mono { Layout.alignment: Qt.AlignTop; Layout.topMargin: 6; text: card.wd.unit; font.pixelSize: 16; color: Pal.muted }
        }
        Mono { text: card.wd.loaded ? card.wd.label(card.wd.code) : (card.wd.failed ? "can't reach weather service" : "loading…") }
      }
      Item { Layout.fillWidth: true }
      ColumnLayout {
        visible: card.wd.loaded
        spacing: 0
        Row { Layout.alignment: Qt.AlignRight; spacing: 7; Mono { text: "↑"; color: Pal.red } Mono { text: card.wd.cv(card.wd.hiC) + "°" } }
        Row { Layout.alignment: Qt.AlignRight; spacing: 7; Mono { text: "↓"; color: Pal.blue } Mono { text: card.wd.cv(card.wd.loC) + "°" } }
      }
    }
    GridLayout {
      visible: card.wd.loaded
      Layout.fillWidth: true
      Layout.topMargin: 10
      columns: 4
      columnSpacing: 10
      rowSpacing: 1
      Mono { text: "feels"; color: Pal.muted }
      Mono { text: card.wd.cv(card.wd.feelsC) + "°"; Layout.fillWidth: true }
      Mono { text: "wind"; color: Pal.muted }
      Row {
        Layout.fillWidth: true
        spacing: 7
        Mono { text: card.wd.fahrenheit ? Math.round(card.wd.windKmh * 0.621) + " mph" : Math.round(card.wd.windKmh) + " km/h" }
        Mono { text: card.wd.compass(card.wd.windDeg); color: Pal.muted }
      }
      Mono { text: "humid"; color: Pal.muted }
      Mono { text: card.wd.humidity + "%"; Layout.fillWidth: true }
      Mono { text: "uv"; color: Pal.muted }
      Row {
        Layout.fillWidth: true
        spacing: 7
        Mono { text: Math.round(card.wd.uv); color: card.wd.uvInfo(card.wd.uv).color }
        Mono { text: card.wd.uvInfo(card.wd.uv).text }
      }
    }
  }
  Box {
    visible: card.size === "R"
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 8; padBottom: 8
    legend: "next 8h"
    rightLegend: card.wd.rainText
    rightColor: card.wd.firstRain >= 0 ? Pal.blue : Pal.cyan
    Row {
      id: hours
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      Repeater {
        model: card.wd.hourly.length
        delegate: Column {
          required property int index
          readonly property var h: card.wd.hourly[index] || ({})
          readonly property var s: card.wd.spec(h.code, h.day)
          width: hours.width / 8
          spacing: 3
          Mono { anchors.horizontalCenter: parent.horizontalCenter; text: parent.h.label || ""; font.pixelSize: 11; color: parent.index === 0 ? Pal.fg : Pal.dim }
          PhIcon { anchors.horizontalCenter: parent.horizontalCenter; name: parent.s.name; fill: parent.s.fill; color: parent.s.color }
          Mono { anchors.horizontalCenter: parent.horizontalCenter; text: card.wd.cv(parent.h.tempC || 0) + "°" }
        }
      }
    }
  }
}

import QtQuick
import ".."
import QtQuick.Layouts

// ===== WEATHER WIDGET =====
// Open-Meteo (free, no API key). Always fetched in metric and converted
// locally, so the u toggle is instant. Location: fixed latitude/longitude if
// set (non-NaN), otherwise a one-time IP geolocation (ipwho.is, also keyless).
DesktopWidget {
  id: root

  // Set both to pin a location; leave NaN to use the IP lookup.
  property real latitude: NaN
  property real longitude: NaN
  property bool fahrenheit: true
  property int refreshMinutes: 20
  property bool showHints: true

  property string place: ""
  property bool loaded: false
  property bool failed: false
  property bool refreshing: false
  property real updatedAt: 0
  property real nowMs: Date.now()

  // current (metric)
  property real tempC: 0
  property real feelsC: 0
  property int code: 0
  property bool isDay: true
  property int humidity: 0
  property real windKmh: 0
  property real windDeg: 0
  property real uv: 0
  property string sunrise: ""
  property string sunset: ""
  property real hiC: 0
  property real loC: 0
  property var hourly: []   // 8 x {label, code, day, tempC, pop}
  property var daily: []    // 5 x {label, code, loC, hiC}

  cardWidth: 360

  function cv(c) { return Math.round(fahrenheit ? c * 9 / 5 + 32 : c); }

  // WMO weather code -> {name, fill, color}
  function spec(c, day) {
    if (c === 0) return day ? { name: "sun", fill: true, color: Pal.yellow } : { name: "moon-stars", fill: false, color: Pal.purple };
    if (c <= 2) return day ? { name: "cloud-sun", fill: true, color: Pal.yellow } : { name: "moon-stars", fill: false, color: Pal.purple };
    if (c === 3) return { name: "cloud", fill: false, color: Pal.dim };
    if (c === 45 || c === 48) return { name: "cloud-fog", fill: false, color: Pal.dim };
    if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return { name: "cloud-rain", fill: false, color: Pal.blue };
    if ((c >= 71 && c <= 77) || c === 85 || c === 86) return { name: "cloud-snow", fill: false, color: Pal.fg };
    if (c >= 95) return { name: "cloud-lightning", fill: false, color: Pal.orange };
    return { name: "cloud", fill: false, color: Pal.dim };
  }
  function label(c) {
    if (c === 0) return "clear";
    if (c === 1) return "mostly clear";
    if (c === 2) return "partly cloudy";
    if (c === 3) return "overcast";
    if (c === 45 || c === 48) return "fog";
    if (c >= 51 && c <= 57) return "drizzle";
    if (c >= 61 && c <= 67) return "rain";
    if (c >= 71 && c <= 77) return "snow";
    if (c >= 80 && c <= 82) return "showers";
    if (c === 85 || c === 86) return "snow showers";
    if (c === 95) return "thunderstorm";
    if (c >= 96) return "thunder, hail";
    return "unknown";
  }
  function compass(deg) {
    return ["n", "ne", "e", "se", "s", "sw", "w", "nw"][Math.round(deg / 45) % 8];
  }
  function uvInfo(u) {
    if (u < 3) return { text: "low", color: Pal.green };
    if (u < 6) return { text: "moderate", color: Pal.yellow };
    if (u < 8) return { text: "high", color: Pal.orange };
    if (u < 11) return { text: "very high", color: Pal.red };
    return { text: "extreme", color: Pal.purple };
  }
  function bar(p) {
    return p > 0 ? "▁▂▃▄▅▆▇█"[Math.min(7, Math.round(p / 100 * 7))] : "·";
  }

  readonly property var dailyRange: {
    let mn = 1e9, mx = -1e9;
    for (const d of daily) { mn = Math.min(mn, d.loC); mx = Math.max(mx, d.hiC); }
    return { min: mn, span: Math.max(1, mx - mn) };
  }
  readonly property int firstRain: {
    for (let i = 0; i < hourly.length; i++) if (hourly[i].pop >= 50) return i;
    return -1;
  }
  readonly property string updatedText: {
    if (refreshing) return "fetching…";
    if (failed && !loaded) return "offline";
    const m = Math.floor((nowMs - updatedAt) / 60000);
    return m < 1 ? "updated just now" : "updated " + m + "m ago";
  }

  function getJson(url, cb, onFail) {
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return;
      if (xhr.status !== 200) { onFail(); return; }
      try { cb(JSON.parse(xhr.responseText)); } catch (e) { onFail(); }
    };
    xhr.timeout = 15000;
    xhr.open("GET", url);
    xhr.send();
  }

  function refresh() {
    if (refreshing) return;
    refreshing = true;
    if (isNaN(latitude) || isNaN(longitude)) {
      getJson("https://ipwho.is/", function (j) {
        if (!j.success) { root.fail(); return; }
        root.latitude = j.latitude;
        root.longitude = j.longitude;
        root.place = (j.city || "").toLowerCase();
        root.fetchForecast();
      }, root.fail);
    } else {
      fetchForecast();
    }
  }
  function fail() { failed = true; refreshing = false; }

  function fetchForecast() {
    const url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + latitude + "&longitude=" + longitude
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m,wind_direction_10m"
      + "&hourly=temperature_2m,precipitation_probability,weather_code,is_day"
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min,uv_index_max,sunrise,sunset"
      + "&timezone=auto&forecast_days=5";
    getJson(url, function (j) {
      const c = j.current, h = j.hourly, d = j.daily;
      root.tempC = c.temperature_2m;
      root.feelsC = c.apparent_temperature;
      root.code = c.weather_code;
      root.isDay = c.is_day === 1;
      root.humidity = c.relative_humidity_2m;
      root.windKmh = c.wind_speed_10m;
      root.windDeg = c.wind_direction_10m;
      root.hiC = d.temperature_2m_max[0];
      root.loC = d.temperature_2m_min[0];
      root.uv = d.uv_index_max[0];
      root.sunrise = d.sunrise[0].slice(11, 16);
      root.sunset = d.sunset[0].slice(11, 16);

      // next 8 hours, starting at the hour we're currently in
      const curHour = c.time.slice(0, 13) + ":00";
      let start = h.time.indexOf(curHour);
      if (start < 0) start = 0;
      const hrs = [];
      for (let i = start; i < Math.min(start + 8, h.time.length); i++) {
        hrs.push({
          label: i === start ? "now" : h.time[i].slice(11, 13),
          time: h.time[i].slice(11, 16),
          code: h.weather_code[i], day: h.is_day[i] === 1,
          tempC: h.temperature_2m[i], pop: h.precipitation_probability[i] || 0
        });
      }
      root.hourly = hrs;

      const out = [];
      for (let i = 0; i < d.time.length; i++) {
        // local noon, dodging the UTC-midnight off-by-one
        const dt = new Date(d.time[i] + "T12:00:00");
        out.push({
          label: i === 0 ? "today" : Qt.formatDate(dt, "ddd").toLowerCase(),
          code: d.weather_code[i], loC: d.temperature_2m_min[i], hiC: d.temperature_2m_max[i]
        });
      }
      root.daily = out;
      root.failed = false;
      root.loaded = true;
      root.refreshing = false;
      root.updatedAt = Date.now();
      root.nowMs = Date.now();
    }, root.fail);
  }

  Component.onCompleted: refresh()
  Timer {
    interval: root.refreshMinutes * 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
  // keeps the "updated Nm ago" text honest
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  onKeyPressed: (e) => {
    if (e.key === Qt.Key_U) { root.fahrenheit = !root.fahrenheit; e.accepted = true; }
    else if (e.key === Qt.Key_R) { root.refresh(); e.accepted = true; }
  }

  // ----- header -----
  RowLayout {
    Layout.fillWidth: true
    Layout.bottomMargin: 8
    spacing: 8
    Mono { text: "weather"; font.weight: Font.Medium; color: root.focused ? Pal.blue : Pal.dim }
    Mono {
      Layout.fillWidth: true
      text: "─ " + (root.place || "locating") + " ─"
      color: Pal.muted
      elide: Text.ElideRight
    }
    TextButton {
      onClicked: root.fahrenheit = !root.fahrenheit
      Mono { text: "u"; color: Pal.yellow }
      Mono { text: root.fahrenheit ? "°F" : "°C"; color: Pal.muted }
    }
    TextButton {
      onClicked: root.refresh()
      Mono { text: "[" + (root.refreshing ? "⟳" : "r") + "]"; color: Pal.muted }
    }
  }

  // ----- now -----
  Box {
    Layout.fillWidth: true
    padTop: 14; padSide: 12; padBottom: 10
    legend: "now"
    rightLegend: root.updatedText
    rightColor: root.refreshing ? Pal.yellow : Pal.muted

    RowLayout {
      Layout.fillWidth: true
      spacing: 14
      PhIcon {
        readonly property var s: root.spec(root.code, root.isDay)
        name: root.loaded ? s.name : "cloud-slash"
        fill: root.loaded && s.fill
        color: root.loaded ? s.color : Pal.muted
        font.pixelSize: 44
      }
      ColumnLayout {
        spacing: 0
        RowLayout {
          spacing: 0
          Mono {
            text: root.loaded ? root.cv(root.tempC) : "--"
            font.pixelSize: 34; font.weight: Font.Medium; font.letterSpacing: -0.7
          }
          Mono {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 6
            text: root.fahrenheit ? "\u00b0F" : "\u00b0C"
            font.pixelSize: 16; color: Pal.muted
          }
        }
        Mono { text: root.loaded ? root.label(root.code) : (root.failed ? "can't reach weather service" : "loading…") }
      }
      Item { Layout.fillWidth: true }
      ColumnLayout {
        visible: root.loaded
        spacing: 0
        Row {
          Layout.alignment: Qt.AlignRight
          spacing: 7
          Mono { text: "↑"; color: Pal.red }
          Mono { text: root.cv(root.hiC) + "°" }
        }
        Row {
          Layout.alignment: Qt.AlignRight
          spacing: 7
          Mono { text: "↓"; color: Pal.blue }
          Mono { text: root.cv(root.loC) + "°" }
        }
      }
    }

    GridLayout {
      visible: root.loaded
      Layout.fillWidth: true
      Layout.topMargin: 10
      columns: 4
      columnSpacing: 10
      rowSpacing: 1
      Mono { text: "feels"; color: Pal.muted }
      Mono { text: root.cv(root.feelsC) + "°"; Layout.fillWidth: true }
      Mono { text: "wind"; color: Pal.muted }
      Row {
        Layout.fillWidth: true
        spacing: 7
        Mono { text: root.fahrenheit ? Math.round(root.windKmh * 0.621) + " mph" : Math.round(root.windKmh) + " km/h" }
        Mono { text: root.compass(root.windDeg); color: Pal.muted }
      }
      Mono { text: "humid"; color: Pal.muted }
      Mono { text: root.humidity + "%"; Layout.fillWidth: true }
      Mono { text: "uv"; color: Pal.muted }
      Row {
        Layout.fillWidth: true
        spacing: 7
        Mono { text: Math.round(root.uv); color: root.uvInfo(root.uv).color }
        Mono { text: root.uvInfo(root.uv).text }
      }
      Mono { text: "rise"; color: Pal.muted }
      Mono { text: root.sunrise; Layout.fillWidth: true }
      Mono { text: "set"; color: Pal.muted }
      Mono { text: root.sunset; color: Pal.orange; Layout.fillWidth: true }
    }
  }

  // ----- next 8h -----
  Box {
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 8; padBottom: 8
    legend: "next 8h"
    rightLegend: root.firstRain >= 0 ? "rain from " + root.hourly[root.firstRain].time : "no rain"
    rightColor: root.firstRain >= 0 ? Pal.cyan : Pal.muted

    Row {
      id: hourlyRow
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      Repeater {
        model: root.hourly
        delegate: Column {
          required property var modelData
          required property int index
          width: hourlyRow.width / 8
          spacing: 3
          readonly property var s: root.spec(modelData.code, modelData.day)
          Mono {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.label; font.pixelSize: 11
            color: index === 0 ? Pal.fg : Pal.muted
          }
          PhIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: parent.s.name; fill: parent.s.fill; color: parent.s.color
          }
          Mono { anchors.horizontalCenter: parent.horizontalCenter; text: root.cv(modelData.tempC) + "°" }
          Mono {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.bar(modelData.pop); color: Pal.cyan; font.pixelSize: 14
          }
          Mono {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.pop > 0 ? modelData.pop + "%" : " "
            font.pixelSize: 10; color: Pal.muted
          }
        }
      }
    }
  }

  // ----- 5 day -----
  Box {
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 14; padSide: 4; padBottom: 6
    legend: "5 day"

    Repeater {
      model: root.daily
      delegate: RowLayout {
        required property var modelData
        required property int index
        readonly property var s: root.spec(modelData.code, true)
        Layout.fillWidth: true
        Layout.leftMargin: 8; Layout.rightMargin: 8
        Layout.preferredHeight: 21
        spacing: 8
        Mono {
          Layout.preferredWidth: 44
          text: modelData.label
          color: index === 0 ? Pal.fg : Pal.dim
        }
        PhIcon {
          Layout.preferredWidth: 18
          name: parent.s.name; fill: parent.s.fill; color: parent.s.color
          font.pixelSize: 14
        }
        Mono {
          Layout.preferredWidth: 30
          horizontalAlignment: Text.AlignRight
          text: root.cv(modelData.loC) + "°"; color: Pal.muted
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 6
          radius: Globals.eyeCandyOff ? 0 : 1
          color: Pal.track
          Rectangle {
            x: (modelData.loC - root.dailyRange.min) / root.dailyRange.span * parent.width
            width: Math.max(2, (modelData.hiC - modelData.loC) / root.dailyRange.span * parent.width)
            height: parent.height
            radius: Globals.eyeCandyOff ? 0 : 1
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: Pal.blue }
              GradientStop { position: 1; color: Pal.yellow }
            }
          }
        }
        Mono { Layout.preferredWidth: 30; text: root.cv(modelData.hiC) + "°" }
      }
    }
  }

  Hints {
    visible: root.showHints
    Layout.fillWidth: true
    Layout.topMargin: 12
    items: [["u", "units"], ["r", "refresh"]]
  }
}

pragma Singleton
import Quickshell
import QtQuick
import "../../widgets"

// Weather for the desktop's weather card (every size reads this one copy).
// Open-Meteo (free, no key), always fetched metric and converted locally so the
// u toggle is instant. Location: fixed latitude/longitude if set, otherwise a
// one-time IP lookup (ipwho.is, keyless) that also names the city.
Singleton {
  id: root

  // Set both to pin a location; NaN uses the IP lookup.
  property real latitude: NaN
  property real longitude: NaN
  property bool fahrenheit: true
  property int refreshMinutes: 20

  property string place: ""
  property bool loaded: false
  property bool failed: false
  property bool refreshing: false
  property real updatedAt: 0
  property real nowMs: Date.now()

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
  property var hourly: []   // 8 x {label, time, code, day, tempC, pop}

  function cv(c) { return Math.round(fahrenheit ? c * 9 / 5 + 32 : c); }
  readonly property string unit: fahrenheit ? "°F" : "°C"

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
  function compass(deg) { return ["n", "ne", "e", "se", "s", "sw", "w", "nw"][Math.round(deg / 45) % 8]; }
  function uvInfo(u) {
    if (u < 3) return { text: "low", color: Pal.green };
    if (u < 6) return { text: "mod", color: Pal.yellow };
    if (u < 8) return { text: "high", color: Pal.orange };
    if (u < 11) return { text: "v.high", color: Pal.red };
    return { text: "extreme", color: Pal.purple };
  }
  readonly property int firstRain: {
    for (let i = 0; i < hourly.length; i++) if (hourly[i].pop >= 50) return i;
    return -1;
  }
  // "dry all day" / "rain from 15:00"
  readonly property string rainText: firstRain >= 0 ? "rain from " + hourly[firstRain].time : "dry all day"
  readonly property string updatedText: {
    if (refreshing) return "fetching…";
    if (failed && !loaded) return "offline";
    const m = Math.floor((nowMs - updatedAt) / 60000);
    return m < 1 ? "updated just now" : "updated " + m + "m ago";
  }
  // One line for a minimized card / the greeting: "64°F · clear · dry all day"
  readonly property string summary: loaded ? cv(tempC) + unit + " · " + label(code) + " · " + rainText
    : (failed ? "offline" : "locating…")

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
        root.place = j.city || "";
        root.fetchForecast();
      }, root.fail);
    } else fetchForecast();
  }
  function fail() { failed = true; refreshing = false; }
  function fetchForecast() {
    const url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + latitude + "&longitude=" + longitude
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m,wind_direction_10m"
      + "&hourly=temperature_2m,precipitation_probability,weather_code,is_day"
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min,uv_index_max,sunrise,sunset"
      + "&timezone=auto&forecast_days=2";
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
      root.failed = false;
      root.loaded = true;
      root.refreshing = false;
      root.updatedAt = Date.now();
      root.nowMs = Date.now();
    }, root.fail);
  }

  Component.onCompleted: refresh()
  Timer { interval: root.refreshMinutes * 60000; running: true; repeat: true; onTriggered: root.refresh() }
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }
}

import QtQuick
import Quickshell.Io

// ----- live currency rates for Convert.js -----
// open.er-api.com's free tier: no API key, no rate-limit auth, and covers
// ~160 currencies (including the Latin American ones the built-in
// hardcoded fallback in Convert.js was missing -- ars/cop/clp/pen/etc.),
// unlike ECB-only sources (frankfurter.app) which don't carry most of
// Latin America at all. The upstream data itself only actually refreshes
// about once every 24h, but polling hourly is cheap and means a stale
// local cache never lingers long after a real update lands.
Item {
  id: root

  // Lowercased ISO code -> USD per 1 unit (e.g. rates.eur ~= 1.087),
  // matching Convert.js's own internal `U.currency` convention exactly so
  // it can be passed straight in. Empty until the first fetch resolves --
  // Convert.js falls back to its own small built-in table until then (or
  // if a fetch ever fails), so conversions still work, just with a less
  // current/less complete rate for anything not in that fallback.
  property var rates: ({})
  property string lastUpdated: ""
  property bool ok: false

  function refresh() {
    if (fetchProc.running) return;
    fetchProc.running = true;
  }

  Process {
    id: fetchProc
    command: ["curl", "-fsS", "--max-time", "10", "https://open.er-api.com/v6/latest/USD"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text);
          if (data.result !== "success" || !data.rates) return;
          const out = {};
          for (const code in data.rates) {
            out[code.toLowerCase()] = 1 / data.rates[code];
          }
          root.rates = out;
          root.lastUpdated = data.time_last_update_utc || "";
          root.ok = true;
        } catch (e) {
          console.warn("CurrencyBackend: failed to parse rates response: " + e);
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim().length > 0) console.warn("CurrencyBackend: curl stderr: " + text.trim());
      }
    }
  }

  Timer {
    interval: 3600000 // 1h
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}

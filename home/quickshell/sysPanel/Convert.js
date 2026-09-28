.pragma library

// Unit/currency converter -- ported near-verbatim from `convEval()` in
// "Quickshell Example/Quickshell Bar.dc.html" (around line 1080). Same
// spirit as Calc.js alongside it: a pure function, no `this.state` to close
// over, returns plain data and lets the caller build the actual list item.
//
// Handles: length, mass, data, time, speed, volume, currency, temperature.
// Parses "5 km to mi", "72 f to c", "$120 to eur", "2.5 gib in mb",
// "180 lb" (bare unit -> a sensible default target, see DEF), plural/alias
// unit names ("kilometers", "pounds", "°f", ...), and currency symbols
// ($€£¥).
//
// Currency rates: `liveRates`, when given, is CurrencyBackend.qml's fetched
// table (lowercased ISO code -> USD per 1 unit, e.g. eur: ~1.087) and wins
// over every entry below -- this hardcoded table only exists as the
// fallback for before that backend's first fetch resolves, or if a fetch
// ever fails outright, so conversions still work rather than going dead.
// It's a fixed, roughly-current snapshot (not live), and only covers a
// handful of currencies -- ars in particular has had extreme, fast-moving
// inflation and is rough even by this table's own non-live standard.
function evaluate(raw, liveRates, ratesUpdated) {
  if (!raw || raw.length > 60) return null;
  const U = {
    length: { mm: 0.001, cm: 0.01, m: 1, km: 1000, in: 0.0254, ft: 0.3048, yd: 0.9144, mi: 1609.344, nmi: 1852 },
    mass: { mg: 1e-6, g: 0.001, kg: 1, t: 1000, oz: 0.028349523125, lb: 0.45359237, st: 6.35029318 },
    data: { b: 1, kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12, kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776 },
    time: { ms: 0.001, s: 1, min: 60, h: 3600, d: 86400, wk: 604800, yr: 31557600 },
    speed: { "m/s": 1, kmh: 1 / 3.6, mph: 0.44704, kn: 0.514444 },
    volume: { ml: 0.001, l: 1, tsp: 0.00492892, tbsp: 0.0147868, floz: 0.0295735, cup: 0.24, pt: 0.473176, gal: 3.78541 },
    currency: Object.assign({
      usd: 1, eur: 1 / 0.92, gbp: 1 / 0.78, jpy: 1 / 147.2, cad: 1 / 1.36, aud: 1 / 1.51, chf: 1 / 0.88, sek: 1 / 10.6, dkk: 1 / 6.86, inr: 1 / 83.4,
      mxn: 1 / 18.5, brl: 1 / 5.5, ars: 1 / 1000, cop: 1 / 4050, clp: 1 / 950, pen: 1 / 3.75,
    }, liveRates || {}),
    temp: { c: 1, f: 1, k: 1 },
  };
  const A = {
    kilometer: "km", kilometers: "km", kilometre: "km", kilometres: "km", meter: "m", meters: "m", metre: "m", metres: "m",
    centimeter: "cm", centimeters: "cm", millimeter: "mm", millimeters: "mm", inch: "in", inches: "in", "\"": "in",
    foot: "ft", feet: "ft", "'": "ft", yard: "yd", yards: "yd", mile: "mi", miles: "mi",
    gram: "g", grams: "g", kilo: "kg", kilos: "kg", kilogram: "kg", kilograms: "kg", pound: "lb", pounds: "lb", lbs: "lb",
    ounce: "oz", ounces: "oz", stone: "st", tonne: "t", tonnes: "t",
    celsius: "c", "°c": "c", fahrenheit: "f", "°f": "f", kelvin: "k", byte: "b", bytes: "b",
    sec: "s", secs: "s", second: "s", seconds: "s", mins: "min", minute: "min", minutes: "min", hr: "h", hrs: "h",
    hour: "h", hours: "h", day: "d", days: "d", week: "wk", weeks: "wk", year: "yr", years: "yr",
    mps: "m/s", "km/h": "kmh", kph: "kmh", knot: "kn", knots: "kn", liter: "l", liters: "l", litre: "l", litres: "l",
    cups: "cup", gallon: "gal", gallons: "gal", dollar: "usd", dollars: "usd", euro: "eur", euros: "eur", yen: "jpy",
  };
  const DEF = {
    km: "mi", mi: "km", m: "ft", ft: "m", cm: "in", in: "cm", mm: "in", yd: "m", kg: "lb", lb: "kg", g: "oz", oz: "g",
    st: "kg", c: "f", f: "c", k: "c", gb: "gib", gib: "gb", mb: "mib", mib: "mb", tb: "tib", tib: "tb", l: "gal", gal: "l",
    ml: "floz", floz: "ml", cup: "ml", kmh: "mph", mph: "kmh", "m/s": "kmh", kn: "kmh", h: "min", min: "s", d: "h",
    wk: "d", yr: "d", s: "ms", usd: "eur", eur: "usd",
  };
  const canon = u => { u = A[u] || u; for (const d in U) if (u in U[d]) return { u, d }; return null; };
  let s = raw.toLowerCase().replace(/[$€£¥]/g, m => " " + { "$": "usd", "€": "eur", "£": "gbp", "¥": "jpy" }[m] + " ").replace(/,/g, "").replace(/\s+/g, " ").trim();
  let m = s.match(/^([a-z]+) (-?\d*\.?\d+(?:e-?\d+)?)(.*)$/);
  if (m && canon(m[1]) && canon(m[1]).d === "currency") s = m[2] + " " + m[1] + m[3];
  m = s.match(/^(-?\d*\.?\d+(?:e-?\d+)?) ?([a-z°"'/]+)(?: (?:to|in|as|->|→) ?([a-z°"'/]+)?)?$/);
  if (!m) return null;
  const n = parseFloat(m[1]), from = canon(m[2]);
  if (!from || !isFinite(n)) return null;
  let to = m[3] ? canon(m[3]) : null;
  if (m[3] && (!to || to.d !== from.d)) return null;
  if (!to) {
    const du = DEF[from.u] || (from.d === "currency" ? "usd" : Object.keys(U[from.d]).find(x => x !== from.u));
    to = { u: du, d: from.d };
  }
  const T = { c: [v => v, v => v], f: [v => (v - 32) * 5 / 9, v => v * 9 / 5 + 32], k: [v => v - 273.15, v => v + 273.15] };
  const cv = (v, a, b) => from.d === "temp" ? T[b][1](T[a][0](v)) : v * U[from.d][a] / U[from.d][b];
  const name = u => ({ c: "°C", f: "°F", k: "K", kmh: "km/h", floz: "fl oz" })[u] || (from.d === "currency" ? u.toUpperCase() : u);
  const fmt = (v, u) => {
    const a = Math.abs(v);
    if (from.d === "currency") return v.toLocaleString("en-US", { minimumFractionDigits: u === "jpy" ? 0 : 2, maximumFractionDigits: u === "jpy" ? 0 : 2 });
    if (a !== 0 && (a < 1e-4 || a >= 1e12)) return v.toExponential(3);
    return (+v.toPrecision(6)).toLocaleString("en-US", { maximumFractionDigits: a < 1 ? 6 : 4 });
  };
  const out = cv(n, from.u, to.u), outS = fmt(out, to.u) + " " + name(to.u), rawOut = String(+out.toPrecision(10));
  const rows = [
    { k: "from", v: fmt(n, from.u) + " " + name(from.u), c: "#abb2bf" },
    { k: "to", v: outS, c: "#e5c07b" },
  ];
  if (from.d === "currency") {
    rows.push({ k: "rate", v: "1 " + name(from.u) + " = " + (U.currency[from.u] / U.currency[to.u]).toFixed(4) + " " + name(to.u), c: "#7f848e" });
    const usingLive = liveRates && (from.u in liveRates || to.u in liveRates);
    rows.push({ k: "source", v: usingLive ? "live · updated " + ratesUpdated : "fixed fallback, not live", c: "#5c6370" });
  } else if (from.d === "temp") {
    rows.push({ k: "also", v: Object.keys(U.temp).filter(x => x !== from.u && x !== to.u).map(x => fmt(cv(n, from.u, x), x) + " " + name(x)).join(" · "), c: "#7f848e" });
  } else {
    Object.keys(U[from.d]).filter(x => x !== from.u && x !== to.u).slice(0, 3)
      .forEach((x, i) => rows.push({ k: i ? "" : "also", v: fmt(cv(n, from.u, x), x) + " " + name(x), c: "#7f848e" }));
  }
  rows.push({ k: "copies", v: rawOut, c: "#7f848e" });
  return {
    ok: true,
    domain: from.d,
    label: "= " + outS,
    sub: fmt(n, from.u) + " " + name(from.u) + " → " + name(to.u),
    rawOut,
    rows,
  };
}

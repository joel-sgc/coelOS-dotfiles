import QtQuick
import Quickshell
import Quickshell.Io

// ===== ETHERNET BACKEND =====
// State + actions for the network dropdown's "3 ethernet" tab
// (EthernetView.qml is the UI; this is everything behind it).
//
// Real data comes from eth-state.sh (nmcli device/connection settings,
// sysfs link info, `ip route`, NetworkManager's shared-mode dnsmasq lease
// files), polled while the tab is open. Everything is held as NetworkManager
// profiles -- a port's "role" is just which settings its profile carries:
//
//   uplink  ipv4.method auto/manual/link-local/disabled
//   share   ipv4.method shared  (NM runs dnsmasq + NAT through the default route)
//   bridge  a bridge-slave profile enslaved to a bridge profile
//   off     device disconnected, profile left alone but autoconnect off
//   host    NOT backed by anything: an isolated/routed subnet with your own
//           DHCP/DNS/PXE needs a standalone dnsmasq + firewall rules, which
//           NetworkManager can't express. The role is shown but cannot be applied.
//
// Edits are staged (`edits`) and only written by apply(), which runs a list
// of real commands as a visible job (one line per command, stopping at the
// first failure). test() runs a read-only diagnostic job the same way.
Item {
  id: be

  property bool active: false
  property int sel: 0
  property bool adv: false
  // { name, title, steps: [{ l, r, state }], defs, i, done }
  property var job: null
  // port name -> { role, cfg }   staged, not yet applied
  property var edits: ({})
  property var ifaces: []
  property var routes: []
  property var otherDevs: ({})
  property int spin: 0
  property var counters: ({})
  property var rates: ({})

  readonly property string script: Qt.resolvedUrl("eth-state.sh").toString().replace("file://", "")
  readonly property bool busy: job !== null && !job.done
  readonly property var spinFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  readonly property string spinner: spinFrames[spin % spinFrames.length]

  // ----- collecting real state -----
  Process {
    id: collect
    command: ["sh", be.script]
    stdout: StdioCollector { onStreamFinished: be.parse(text) }
  }
  function refresh() { if (!collect.running) collect.running = true; }
  Timer {
    interval: 3000
    running: be.active
    repeat: true
    triggeredOnStart: true
    onTriggered: be.refresh()
  }
  Timer {
    interval: 110
    running: be.active && be.busy
    repeat: true
    onTriggered: be.spin = be.spin + 1
  }

  readonly property var ip4Map: ({ "auto": "DHCP", "manual": "Manual", "link-local": "Link-local only", "disabled": "Disabled" })
  readonly property var ip4Rev: ({ "DHCP": "auto", "Manual": "manual", "Link-local only": "link-local", "Disabled": "disabled" })
  readonly property var ip6Map: ({ "auto": "Auto (SLAAC)", "dhcp": "DHCPv6", "link-local": "Link-local only", "disabled": "Disabled", "ignore": "Disabled", "shared": "Auto (SLAAC)" })
  readonly property var ip6Rev: ({ "Auto (SLAAC)": "auto", "DHCPv6": "dhcp", "Link-local only": "link-local", "Disabled": "disabled" })
  readonly property var macMap: ({ "": "Permanent", "permanent": "Permanent", "stable": "Stable per network", "random": "Random" })
  readonly property var macRev: ({ "Permanent": "permanent", "Stable per network": "stable", "Random": "random" })

  function speedText(raw) {
    const n = parseInt(raw);
    if (!(n > 0)) return "";
    return n >= 1000 ? (n / 1000) + " Gb/s" : n + " Mb/s";
  }

  function liveRole(f) {
    if (f.cf["connection.master"]) return "bridge";
    if (!f.conn) return "off";
    if (f.state.indexOf("connected") !== 0) return "off";
    if (f.cf["ipv4.method"] === "shared") return "share";
    return "uplink";
  }

  function parse(text) {
    const by = {}, order = [], routes = [], neigh = {}, other = {};
    for (const line of text.split("\n")) {
      if (!line) continue;
      const f = line.split("\t");
      if (f[0] === "IF") {
        by[f[1]] = { name: f[1], type: f[2], state: f[3], conn: f[4], carrier: f[5] === "1", speedRaw: f[6], mac: f[7], kind: f[8], chip: f[9], parent: f[10], vid: f[11],
          cf: {}, live: { ip4: "", gw: "", dns: [], ip6: "" }, leases: [], rx: 0, tx: 0 };
        order.push(f[1]);
      } else if (f[0] === "CF" && by[f[1]]) {
        by[f[1]].cf[f[2]] = f.slice(3).join("\t");
      } else if (f[0] === "LIVE" && by[f[1]]) {
        const key = f[2], val = f.slice(3).join("\t"), L = by[f[1]].live;
        if (key.indexOf("IP4.ADDRESS") === 0 && !L.ip4) L.ip4 = val;
        else if (key === "IP4.GATEWAY") L.gw = val;
        else if (key.indexOf("IP4.DNS") === 0) L.dns.push(val);
        else if (key.indexOf("IP6.ADDRESS") === 0 && !L.ip6) L.ip6 = val;
      } else if (f[0] === "CT" && by[f[1]]) {
        by[f[1]].rx = parseFloat(f[2]) || 0; by[f[1]].tx = parseFloat(f[3]) || 0;
      } else if (f[0] === "LS" && by[f[1]]) {
        const p = f[2].trim().split(/\s+/);
        if (p.length >= 4) by[f[1]].leases.push({ expiry: parseInt(p[0]), mac: p[1], ip: p[2], name: p[3] === "*" ? "unknown device" : p[3] });
      } else if (f[0] === "RT") {
        routes.push(f[1]);
      } else if (f[0] === "NB") {
        neigh[f[1]] = f[2];
      } else if (f[0] === "DV") {
        other[f[1]] = { type: f[2], state: f[3], conn: f[4] };
      }
    }

    // rx/tx rates from the counters of the previous poll
    const now = Date.now(), rates = {}, counters = {};
    for (const n of order) {
      const f = by[n], prev = be.counters[n];
      counters[n] = { rx: f.rx, tx: f.tx, t: now };
      if (prev && now > prev.t && f.rx >= prev.rx) {
        const dt = (now - prev.t) / 1000;
        rates[n] = { rx: (f.rx - prev.rx) / dt, tx: (f.tx - prev.tx) / dt };
      }
    }
    be.counters = counters;
    be.rates = rates;

    const nowS = Math.floor(now / 1000);
    const list = order.map(n => {
      const f = by[n];
      f.speed = be.speedText(f.speedRaw);
      f.live_role = be.liveRole(f);
      f.since = (parseInt(f.cf["connection.timestamp"]) || 0) * 1000;
      f.leases = f.leases.filter(l => !(l.expiry > 0 && l.expiry < nowS)).map(l => Object.assign({}, l, {
        left: l.expiry === 0 ? "∞" : be.fmtLeft(l.expiry - nowS),
        online: ["REACHABLE", "STALE", "DELAY", "PROBE"].indexOf(neigh[l.ip] || "") >= 0 }));
      return f;
    });
    // VLANs sit directly under their parent
    const parents = list.filter(f => f.type !== "vlan"), vlans = list.filter(f => f.type === "vlan");
    const sorted = [];
    for (const p of parents) { sorted.push(p); for (const v of vlans) if (v.parent === p.name) sorted.push(v); }
    for (const v of vlans) if (sorted.indexOf(v) < 0) sorted.push(v);

    be.ifaces = sorted;
    be.routes = routes;
    be.otherDevs = other;
    if (be.sel >= sorted.length) be.sel = Math.max(0, sorted.length - 1);
  }

  function fmtLeft(s) {
    if (s < 90) return Math.max(0, s) + "s";
    if (s < 5400) return Math.round(s / 60) + "m";
    if (s < 172800) return Math.round(s / 3600) + "h";
    return Math.round(s / 86400) + "d";
  }
  function ago(t) {
    const m = Math.floor((Date.now() - t) / 60000);
    return m < 60 ? Math.max(0, m) + "m" : Math.floor(m / 60) + "h " + (m % 60) + "m";
  }
  function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
  function ethBase(cidr) { return (cidr || "").split("/")[0].split(".").slice(0, 3).join("."); }
  function ethNet(cidr) { const p = (cidr || "").split("/"); return ethBase(p[0]) + ".0/" + (p[1] || "24"); }

  // ----- routing view -----
  readonly property var defaults: {
    const out = [];
    for (const l of routes) {
      if (l.indexOf("default") !== 0 || l.indexOf("linkdown") >= 0) continue;
      const via = (l.match(/via (\S+)/) || [])[1] || "", dev = (l.match(/dev (\S+)/) || [])[1] || "";
      const metric = parseInt((l.match(/metric (\d+)/) || [])[1]) || 0;
      out.push({ dev: dev, gw: via, metric: metric });
    }
    return out.sort((a, b) => a.metric - b.metric);
  }
  readonly property var inet: defaults.length > 0 ? defaults[0] : null

  function devLabel(dev) {
    const w = ifaces.find(x => x.name === dev);
    if (w) return w.conn ? dev + " · " + w.conn : dev;
    const o = otherDevs[dev];
    return o && o.conn ? dev + " · " + o.conn : dev;
  }
  function upstreamOf(i) {
    const d = defaults.find(x => x.dev !== i.name);
    return d ? { dev: d.dev, ok: true, why: devLabel(d.dev) } : { dev: null, ok: false, why: "no default route" };
  }

  // ----- staged edits -----
  function ethDef(i) {
    return {
      ip4: "DHCP", addr: "", gw: "", dns: "", ip6: "Auto (SLAAC)", prio: "Prefer over Wi‑Fi",
      mtu: "1500", mac: "Permanent", auth: "None", ident: "", epass: "", epassShow: false, auto: true, metered: false, wol: false, lldp: false,
      gw4: "10.42.1.1/24", v6share: false,
      net: "192.168.50.1/24", range: "192.168.50.100 – .200", lease: "12h", domain: "lab.lan", route: "Isolated (no internet)", pxe: false, dnsLocal: true,
      br: "br0", members: [], stp: true, brIp: "DHCP"
    };
  }
  // The settings the port really has right now, in the form's own terms.
  function liveCfg(i) {
    const c = ethDef(i), cf = i.cf;
    if (!i.conn && !i.live.ip4) return c;
    const m = cf["ipv4.method"];
    if (m && m !== "shared") c.ip4 = ip4Map[m] || "DHCP";
    const addr = (cf["ipv4.addresses"] || "").split(",")[0].trim();
    if (c.ip4 === "Manual") { c.addr = addr; c.gw = cf["ipv4.gateway"] || ""; }
    c.dns = (cf["ipv4.dns"] || "").replace(/,/g, ", ").trim();
    const metric = parseInt(cf["ipv4.route-metric"]);
    c.prio = cf["ipv4.never-default"] === "yes" ? "Never default route" : (metric > 600 ? "Fallback after Wi‑Fi" : "Prefer over Wi‑Fi");
    const m6 = cf["ipv6.method"];
    if (m6 && m6 !== "shared") c.ip6 = ip6Map[m6] || "Auto (SLAAC)";
    const mtu = cf["802-3-ethernet.mtu"];
    c.mtu = mtu && mtu !== "auto" ? mtu : "1500";
    c.mac = macMap[cf["802-3-ethernet.cloned-mac-address"] || ""] || "Permanent";
    c.auth = cf["802-1x.eap"] === "peap" ? "802.1X · PEAP/MSCHAPv2" : "None";
    c.ident = cf["802-1x.identity"] || "";
    c.auto = cf["connection.autoconnect"] !== "no";
    c.metered = cf["connection.metered"] === "yes";
    c.wol = cf["802-3-ethernet.wake-on-lan"] === "magic";
    c.lldp = cf["connection.lldp"] === "enable-rx" || cf["connection.lldp"] === "yes";
    if (m === "shared") { c.gw4 = i.live.ip4 || addr || c.gw4; c.v6share = m6 === "shared"; }
    const master = cf["connection.master"];
    if (master) {
      c.br = master;
      c.members = ifaces.filter(x => x.name !== i.name && x.cf["connection.master"] === master).map(x => x.name);
    }
    return c;
  }
  function roleOf(i) { return edits[i.name] && edits[i.name].role ? edits[i.name].role : i.live_role; }
  function cfgOf(i) { return Object.assign({}, liveCfg(i), edits[i.name] ? edits[i.name].cfg : {}); }
  function isDirty(i) {
    const e = edits[i.name];
    if (!e) return false;
    return (e.role && e.role !== i.live_role) || JSON.stringify(cfgOf(i)) !== JSON.stringify(liveCfg(i));
  }
  function setEdit(name, patch) {
    const next = Object.assign({}, edits), cur = next[name] || { role: null, cfg: {} };
    next[name] = { role: patch.role !== undefined ? patch.role : cur.role, cfg: Object.assign({}, cur.cfg, patch.cfg || {}) };
    edits = next;
  }
  function selected() { return ifaces.length > 0 ? ifaces[Math.min(sel, ifaces.length - 1)] : null; }
  function setRole(r) { const i = selected(); if (i) setEdit(i.name, { role: r }); }
  function setCfg(patch) { const i = selected(); if (i) setEdit(i.name, { cfg: patch }); }
  function revert() { const i = selected(); if (!i) return; const next = Object.assign({}, edits); delete next[i.name]; edits = next; }

  // ----- job runner: one real shell command per line, stop on first failure -----
  Process {
    id: runner
    stdout: StdioCollector { onStreamFinished: be.stepFinished(text) }
  }
  function runJob(name, title, defs, onDone) {
    if (busy) return;
    job = { name: name, title: title, defs: defs, onDone: onDone || null, i: 0, done: false,
      steps: defs.map(d => ({ l: d.l, r: "", state: "wait" })) };
    nextStep();
  }
  function nextStep() {
    const j = job;
    if (!j) return;
    if (j.i >= j.defs.length) { finishJob(); return; }
    const d = j.defs[j.i];
    if (d.fn) { applyResult(d.fn()); return; }
    runner.command = ["sh", "-c", "{ " + d.cmd + "; } 2>&1; echo __RC__$?"];
    runner.running = true;
  }
  function stepFinished(text) {
    const j = job;
    if (!j || j.done) return;
    const at = text.lastIndexOf("__RC__"), out = (at >= 0 ? text.slice(0, at) : text).trim(), rc = at >= 0 ? parseInt(text.slice(at + 6)) : 1;
    const d = j.defs[j.i];
    const first = out.split("\n").filter(x => x.trim().length > 0).slice(-1)[0] || "";
    applyResult(d.parse ? d.parse(out, rc) : (rc === 0 ? { r: d.ok || "ok" } : { r: first.slice(0, 70) || "failed (exit " + rc + ")", bad: true, stop: true }));
  }
  function applyResult(res) {
    const j = job;
    const steps = j.steps.map((s, n) => n === j.i ? { l: s.l, r: res.r || "", state: res.bad ? "bad" : res.warn ? "warn" : "ok" } : s);
    const stop = !!res.stop;
    job = Object.assign({}, j, { steps: steps, i: stop ? steps.length : j.i + 1, stopped: stop });
    if (stop) { finishJob(); return; }
    nextStep();
  }
  function finishJob() {
    const j = job;
    if (!j) return;
    job = Object.assign({}, j, { done: true });
    if (j.onDone) j.onDone(!j.stopped);
    refresh();
  }
  function dismissJob() { if (job && job.done) job = null; }

  // ----- apply -----
  function connFor(i, role) {
    // a bridge-slave profile can't carry ip settings, so leaving the bridge uses a fresh plain profile
    if (i.conn && !i.cf["connection.master"] && i.type !== "vlan") return i.conn;
    if (i.type === "vlan" && i.conn) return i.conn;
    return "Wired · " + i.name;
  }
  function ensureProfile(i, conn) {
    if (i.conn === conn) return null;
    return { l: "create profile \"" + conn + "\"",
      cmd: "nmcli connection show " + q(conn) + " >/dev/null 2>&1 || nmcli connection add type ethernet ifname " + q(i.name) + " con-name " + q(conn) + " connection.autoconnect yes",
      ok: "ready" };
  }
  function applySteps(i) {
    const r = roleOf(i), c = cfgOf(i), name = i.name;
    const steps = [];
    if (r === "host") {
      return [{ l: "host role", fn: () => ({ r: "needs a standalone dnsmasq + firewall (not available)", warn: true, stop: true }) }];
    }
    if (r === "off") {
      steps.push({ l: "disconnect " + name, cmd: "nmcli device disconnect " + q(name) + " || true", ok: "ok" });
      if (i.conn && !i.cf["connection.master"])
        steps.push({ l: "turn off autoconnect", cmd: "nmcli connection modify " + q(i.conn) + " connection.autoconnect no", ok: "ok" });
      return steps;
    }
    if (r === "bridge") {
      const br = c.br || "br0", members = [name].concat((c.members || []).filter(x => x !== name));
      steps.push({ l: "create bridge " + br,
        cmd: "nmcli connection show " + q(br) + " >/dev/null 2>&1 || nmcli connection add type bridge ifname " + q(br) + " con-name " + q(br) + " bridge.stp " + (c.stp ? "yes" : "no") + " ipv4.method " + (c.brIp === "DHCP" ? "auto" : "disabled") + (c.brIp === "DHCP" ? "" : " ipv6.method ignore"),
        ok: "ok" });
      steps.push({ l: "bridge settings", cmd: "nmcli connection modify " + q(br) + " bridge.stp " + (c.stp ? "yes" : "no") + " ipv4.method " + (c.brIp === "DHCP" ? "auto" : "disabled"), ok: "stp " + (c.stp ? "on" : "off") });
      for (const m of members) {
        const slave = br + " slave " + m;
        steps.push({ l: "enslave " + m,
          cmd: "nmcli connection show " + q(slave) + " >/dev/null 2>&1 || nmcli connection add type bridge-slave ifname " + q(m) + " con-name " + q(slave) + " master " + q(br) + "; nmcli connection up " + q(slave),
          ok: "ok" });
      }
      steps.push({ l: "bring up " + br, cmd: "nmcli connection up " + q(br), ok: "ok" });
      return steps;
    }
    const conn = connFor(i, r);
    const ensure = ensureProfile(i, conn);
    if (i.cf["connection.master"]) steps.push({ l: "leave bridge " + i.cf["connection.master"], cmd: "nmcli connection delete " + q(i.conn), ok: "ok" });
    if (ensure) steps.push(ensure);
    if (r === "uplink") {
      const m = ip4Rev[c.ip4] || "auto";
      let mod = "nmcli connection modify " + q(conn) + " connection.master '' connection.slave-type '' ipv4.method " + m +
        " ipv4.addresses " + (m === "manual" ? q(c.addr) : "''") + " ipv4.gateway " + (m === "manual" ? q(c.gw) : "''") +
        " ipv4.dns " + q((c.dns || "").replace(/,/g, " ")) +
        " ipv4.route-metric " + (c.prio === "Fallback after Wi‑Fi" ? 700 : 100) + " ipv4.never-default " + (c.prio === "Never default route" || m === "disabled" || m === "link-local" ? "yes" : "no") +
        " ipv6.method " + (ip6Rev[c.ip6] || "auto") +
        " connection.autoconnect " + (c.auto ? "yes" : "no") + " connection.metered " + (c.metered ? "yes" : "unknown") +
        " connection.lldp " + (c.lldp ? "enable-rx" : "default");
      // A vlan profile has no 802-3-ethernet / 802-1x sections: nmcli rejects them.
      if (i.type !== "vlan") {
        const mtu = parseInt(c.mtu);
        mod += " 802-3-ethernet.cloned-mac-address " + (macRev[c.mac] || "permanent") +
          " 802-3-ethernet.wake-on-lan " + (c.wol ? "magic" : "default") +
          " 802-3-ethernet.mtu " + (mtu > 0 && mtu !== 1500 ? mtu : "auto");
        if (c.auth !== "None") mod += " 802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity " + q(c.ident) + (c.epass ? " 802-1x.password " + q(c.epass) : "");
        else mod += " 802-1x.eap ''";
      }
      steps.push({ l: "write profile \"" + conn + "\"", cmd: mod, ok: "saved" });
      steps.push({ l: "bring link up", cmd: "nmcli -w 20 connection up " + q(conn) + (i.type === "vlan" ? "" : " ifname " + q(name)) + " 2>&1", ok: i.speed ? i.speed + " full-duplex" : "up",
        parse: (out, rc) => rc === 0 ? { r: i.speed ? i.speed + " full-duplex" : "up" } : { r: out.split("\n").slice(-1)[0].slice(0, 70), bad: true, stop: true } });
      steps.push({ l: "address", cmd: "nmcli -g IP4.ADDRESS device show " + q(name) + " | head -n 1",
        parse: (out) => out ? { r: out } : { r: "none yet", warn: true } });
      steps.push({ l: "default route", cmd: "ip -4 route show default dev " + q(name) + " | head -n 1",
        parse: (out) => out ? { r: "metric " + ((out.match(/metric (\d+)/) || [])[1] || "—") } : { r: "not installed", warn: true } });
      steps.push({ l: "connectivity check", cmd: "nmcli networking connectivity check",
        parse: (out) => ({ r: out, warn: out !== "full" }) });
      return steps;
    }
    // share
    const gw = (c.gw4 || "").split("/")[0];
    steps.push({ l: "write profile \"" + conn + "\"",
      cmd: "nmcli connection modify " + q(conn) + " connection.master '' connection.slave-type '' ipv4.method shared ipv4.addresses " + q(c.gw4) + " ipv4.gateway '' ipv4.dns '' ipv6.method " + (c.v6share ? "shared" : "link-local") +
        " connection.autoconnect yes",
      ok: "saved" });
    steps.push({ l: "bring link up", cmd: "nmcli connection up " + q(conn) + (i.type === "vlan" ? "" : " ifname " + q(name)) + " 2>&1",
      parse: (out, rc) => rc === 0 ? { r: c.gw4 } : { r: out.split("\n").slice(-1)[0].slice(0, 70), bad: true, stop: true } });
    steps.push({ l: "net.ipv4.ip_forward", cmd: "cat /proc/sys/net/ipv4/ip_forward", parse: (out) => ({ r: out, warn: out !== "1" }) });
    const up = upstreamOf(i);
    steps.push({ l: "nat → " + (up.dev || "upstream"), fn: () => up.ok ? { r: up.why } : { r: up.why, warn: true } });
    steps.push({ l: "dnsmasq · dhcp on " + gw, cmd: "pgrep -f " + q("dnsmasq.*listen-address=" + gw) + " | head -n 1",
      parse: (out) => out ? { r: "pid " + out } : { r: "not running", warn: true } });
    return steps;
  }
  function apply() {
    const i = selected();
    if (!i || busy) return;
    const name = i.name;
    runJob(name, "apply ─ " + name, applySteps(i), ok => {
      if (ok) { const next = Object.assign({}, be.edits); delete next[name]; be.edits = next; }
    });
  }

  // ----- diagnostics -----
  function test() {
    const i = selected();
    if (!i || busy) return;
    const r = i.live_role, c = liveCfg(i), name = i.name, st = [];
    if (r !== "off" && !i.carrier) {
      st.push({ l: "carrier", fn: () => ({ r: "no cable detected", bad: true, stop: true }) });
    } else if (r === "uplink") {
      const gw = c.ip4 === "Manual" ? c.gw : (i.live.gw || "");
      st.push({ l: "carrier", fn: () => ({ r: (i.speed ? i.speed + " full" : "up") + (i.chip ? " · " + i.chip : "") }) });
      st.push({ l: "address", fn: () => i.live.ip4 ? { r: i.live.ip4 } : { r: "none", bad: true, stop: true } });
      if (gw) st.push({ l: "ping gateway " + gw, cmd: "ping -c 3 -W 1 -I " + q(name) + " " + q(gw) + " | tail -n 2",
        parse: (out, rc) => rc === 0 ? { r: ((out.match(/= [\d.]+\/([\d.]+)\//) || [])[1] || "?") + " ms · 0% loss" } : { r: "no reply", warn: true } });
      st.push({ l: "resolve archlinux.org", cmd: "getent hosts archlinux.org | head -n 1", parse: (out, rc) => rc === 0 && out ? { r: "ok" } : { r: "failed", bad: true } });
      if (c.prio === "Never default route") st.push({ l: "internet", fn: () => ({ r: "not routed via " + name, warn: true }) });
      else st.push({ l: "ping 1.1.1.1", cmd: "ping -c 2 -W 2 -I " + q(name) + " 1.1.1.1 | tail -n 1",
        parse: (out, rc) => rc === 0 ? { r: ((out.match(/= [\d.]+\/([\d.]+)\//) || [])[1] || "?") + " ms" } : { r: "unreachable", warn: true } });
    } else if (r === "share") {
      const up = upstreamOf(i), gw = (c.gw4 || "").split("/")[0];
      st.push({ l: "ip_forward", cmd: "cat /proc/sys/net/ipv4/ip_forward", parse: (out) => ({ r: out, warn: out !== "1" }) });
      st.push({ l: "upstream", fn: () => ({ r: up.why, bad: !up.ok }) });
      st.push({ l: "dnsmasq", cmd: "pgrep -f " + q("dnsmasq.*listen-address=" + gw) + " | head -n 1",
        parse: (out) => out ? { r: "running · " + i.leases.length + " lease(s)" } : { r: "not running", bad: true } });
      if (i.leases[0]) st.push({ l: "ping " + i.leases[0].name, cmd: "ping -c 2 -W 1 " + q(i.leases[0].ip) + " | tail -n 1",
        parse: (out, rc) => rc === 0 ? { r: ((out.match(/= [\d.]+\/([\d.]+)\//) || [])[1] || "?") + " ms" } : { r: "no reply", warn: true } });
    } else if (r === "bridge") {
      const br = c.br;
      st.push({ l: br, cmd: "ip -br link show " + q(br), parse: (out, rc) => rc === 0 ? { r: out.split(/\s+/)[1] || "up" } : { r: "missing", bad: true } });
      st.push({ l: "stp state", cmd: "cat /sys/class/net/" + br + "/bridge/stp_state", parse: (out) => ({ r: out === "1" ? "enabled" : "disabled" }) });
      st.push({ l: "ports", cmd: "ls /sys/class/net/" + br + "/brif | tr '\\n' ' '", parse: (out) => ({ r: out || "none" }) });
    } else {
      st.push({ l: "link", fn: () => ({ r: "administratively down" }) });
    }
    runJob(name, "diagnostics ─ " + name, st);
  }

  // ----- vlan -----
  function addVlan() {
    const p = selected();
    if (!p || p.type === "vlan" || busy) return;
    // Linux interface names are capped at 15 characters, and names like
    // enp195s0f3u1u2 leave no room for ".10", so fall back to "vlan<id>".
    const taken = ifaces.map(x => x.name);
    const nameFor = v => (p.name + "." + v).length <= 15 ? p.name + "." + v : "vlan" + v;
    let vid = 10;
    while (taken.indexOf(nameFor(vid)) >= 0) vid += 10;
    const name = nameFor(vid), conn = "VLAN " + name;
    runJob(name, "new vlan ─ " + name, [{ l: "create " + name,
      cmd: "nmcli connection add type vlan con-name " + q(conn) + " ifname " + q(name) + " dev " + q(p.name) + " id " + vid + " ipv4.method disabled ipv6.method ignore connection.autoconnect no", ok: "vlan " + vid + " on " + p.name }],
      ok => { if (ok) be.pendingSelect = name; });
  }
  property string pendingSelect: ""
  onIfacesChanged: {
    if (pendingSelect) {
      const n = ifaces.findIndex(x => x.name === pendingSelect);
      if (n >= 0) { sel = n; pendingSelect = ""; }
    }
  }
  function deleteVlan() {
    const i = selected();
    if (!i || i.type !== "vlan" || busy) return;
    runJob(i.name, "delete vlan ─ " + i.name, [{ l: "remove profile", cmd: "nmcli connection delete " + q(i.conn || ("VLAN " + i.name)), ok: "deleted" }],
      ok => { if (ok) be.sel = Math.max(0, be.sel - 1); });
  }

  // ----- keys (called from NetworkDropdown's Keys.onPressed) -----
  function handleKey(event) {
    const n = ifaces.length, k = event.key;
    const roles = { [Qt.Key_U]: "uplink", [Qt.Key_S]: "share", [Qt.Key_H]: "host", [Qt.Key_B]: "bridge", [Qt.Key_O]: "off" };
    if (k === Qt.Key_J || k === Qt.Key_Down) sel = Math.min(n - 1, sel + 1);
    else if (k === Qt.Key_K || k === Qt.Key_Up) sel = Math.max(0, sel - 1);
    else if (roles[k] !== undefined) setRole(roles[k]);
    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_A) apply();
    else if (k === Qt.Key_T) test();
    else if (k === Qt.Key_V) addVlan();
    else if (k === Qt.Key_M) adv = !adv;
    else if (k === Qt.Key_X) revert();
    else if (k === Qt.Key_Delete || k === Qt.Key_Backspace) deleteVlan();
    else return false;
    return true;
  }

  // ----- the view model -----
  readonly property var roleColors: ({ uplink: "#89ca78", share: "#d19a66", host: "#d55fde", bridge: "#61afef", off: "#5c6370" })
  readonly property var roleLabels: ({ uplink: "internet", share: "share", host: "subnet", bridge: "bridge", off: "off" })
  readonly property var roleList: [
    ["uplink", "u", "Use this port as your network connection: take an address from the router and route internet through it."],
    ["share", "s", "Share another connection out of this port. NAT + DHCP, so the machine on the other end gets online through you."],
    ["host", "h", "Run your own subnet on this port: you are the gateway, DHCP and DNS. (Not available: NetworkManager can't do an isolated subnet.)"],
    ["bridge", "b", "Join this port into a layer‑2 bridge with VMs or other ports, so they sit on the same network as you."],
    ["off", "o", "Leave the port down and unmanaged."]
  ]

  readonly property var vals: computeVals()

  function computeVals() {
    const i = selected();
    const E = { adv: adv, job: job };
    const inetDev = inet ? inet.dev : "";
    const rows = ifaces.map((x, n) => {
      const d = isDirty(x), live = x.live_role;
      return {
        name: x.name, kind: x.type === "vlan" ? "vlan " + x.vid : x.kind, sel: n === Math.min(sel, ifaces.length - 1),
        iconName: x.type === "vlan" ? "tree-structure" : x.kind === "onboard" ? "desktop-tower" : x.kind === "usb" ? "plug" : "plugs",
        iconColor: x.carrier && live !== "off" ? roleColors[live] : "#5c6370",
        link: !x.carrier ? "○ no cable" : live === "off" ? "◌ down" : "● " + (x.speed || "up"),
        linkColor: !x.carrier || live === "off" ? "#5c6370" : "#89ca78",
        role: roleLabels[live] + (d ? "*" : ""), roleColor: d ? "#e5c07b" : roleColors[live],
        isInet: inetDev === x.name, select: () => { be.sel = n; }
      };
    });
    const routeRows = [];
    defaults.forEach((d, n) => routeRows.push({ mark: n === 0 ? "▸" : "", dest: "default", via: d.gw + " dev " + d.dev, metric: "metric " + d.metric, color: n === 0 ? "#89ca78" : "#abb2bf" }));
    for (const l of routes) {
      if (l.indexOf("default") === 0 || l.indexOf("linkdown") >= 0) continue;
      const p = l.split(/\s+/), dev = (l.match(/dev (\S+)/) || [])[1] || "", metric = (l.match(/metric (\d+)/) || [])[1];
      const w = ifaces.find(x => x.name === dev);
      const note = w && w.live_role === "share" ? " · nat → " + (upstreamOf(w).dev || "—") : "";
      routeRows.push({ mark: "", dest: p[0], via: "dev " + dev + note, metric: metric ? "metric " + metric : "link", color: w && w.live_role === "share" ? "#d19a66" : "#abb2bf" });
    }
    if (routeRows.length === 0) routeRows.push({ mark: "", dest: "—", via: "no routes", metric: "", color: "#5c6370" });

    const base = { count: ifaces.length, rows: rows, routes: routeRows,
      inetLabel: inet ? "internet via " + inet.dev : "no internet", inetColor: inet ? "#89ca78" : "#ef596f", adv: adv, advLabel: adv ? "[−] fewer" : "[+] advanced" };
    if (!i) return Object.assign(base, { empty: true });

    const role = roleOf(i), c = cfgOf(i), lc = liveCfg(i), dirty = isDirty(i);
    const busyHere = busy && job.name === i.name;
    const set = patch => setCfg(patch);
    const cyc = (arr, v) => arr[(arr.indexOf(v) + 1) % arr.length];
    const box = (v, label, toggle, title) => ({ box: v ? "[x]" : "[ ]", color: v ? "#2bbac5" : "#5c6370", label: label, toggle: toggle, title: title || "" });
    const cycle = (label, key, opts, indent) => ({ type: "cycle", label: label, value: c[key], cycle: () => set({ [key]: cyc(opts, c[key]) }), indent: indent ? 12 : 0 });
    const input = (label, key, ph, indent, extra) => Object.assign({ type: "input", label: label, value: c[key], ph: ph || "", change: v => set({ [key]: v }), indent: indent ? 12 : 0, password: false }, extra || {});
    const note = (label, value, color) => ({ type: "note", label: label, value: value, color: color || "#5c6370", indent: 0 });
    const checks = (label, list) => ({ type: "checks", label: label, checks: list, indent: 0 });

    const F = [];
    if (i.type === "vlan") F.push(note("vlan", "id " + i.vid + " · tagged on " + i.parent, "#abb2bf"));
    if (role === "uplink") {
      F.push(cycle("ipv4", "ip4", ["DHCP", "Manual", "Link-local only", "Disabled"]));
      if (c.ip4 === "Manual") { F.push(input("address", "addr", "192.168.1.57/24", true)); F.push(input("gateway", "gw", "192.168.1.1", true)); }
      F.push(input("dns", "dns", "automatic (from dhcp)"));
      F.push(cycle("default route", "prio", ["Prefer over Wi‑Fi", "Fallback after Wi‑Fi", "Never default route"]));
      F.push(note("", c.prio === "Prefer over Wi‑Fi" ? "metric 100 — internet goes over the cable whenever it is plugged in; wi‑fi stays up as fallback" : c.prio === "Fallback after Wi‑Fi" ? "metric 700 — used only when wi‑fi is down" : "lan access only — no internet traffic over this port"));
      if (adv) {
        F.push(cycle("ipv6", "ip6", ["Auto (SLAAC)", "DHCPv6", "Link-local only", "Disabled"]));
        F.push(input("mtu", "mtu", "1500"));
        F.push(cycle("mac address", "mac", ["Permanent", "Stable per network", "Random"]));
        F.push(cycle("auth", "auth", ["None", "802.1X · PEAP/MSCHAPv2"]));
        if (c.auth !== "None") {
          F.push(input("identity", "ident", "username", true));
          F.push(input("password", "epass", "enter password", true, { password: !c.epassShow, hasShow: true, showLabel: c.epassShow ? "[hide]" : "[show]", toggleShow: () => set({ epassShow: !c.epassShow }) }));
        }
      }
      F.push(checks("", [box(c.auto, "autoconnect", () => set({ auto: !c.auto })), box(c.metered, "metered", () => set({ metered: !c.metered })),
        ...(adv ? [box(c.wol, "wake-on-lan", () => set({ wol: !c.wol }), "ethtool -s wol g"), box(c.lldp, "lldp", () => set({ lldp: !c.lldp }))] : [])]));
    } else if (role === "share") {
      const up = upstreamOf(i);
      F.push(note("share from", up.ok ? up.why + " (default route, automatic)" : "no default route", "#abb2bf"));
      F.push(note("", up.ok ? "→ clients reach the internet through " + up.why : "⚠ " + up.why + " — clients will get an address but no internet", up.ok ? "#89ca78" : "#e5c07b"));
      F.push(input("gateway / subnet", "gw4", "10.42.1.1/24"));
      F.push(note("dhcp & dns", "run by NetworkManager's own dnsmasq; always on while sharing"));
      if (adv) F.push(input("mtu", "mtu", "1500"));
      F.push(checks("", [box(c.v6share, "share ipv6", () => set({ v6share: !c.v6share }))]));
    } else if (role === "host") {
      F.push(note("", "unavailable: NetworkManager can only share a connection (NAT + DHCP). An isolated or routed subnet with your own DHCP/DNS/PXE needs a standalone dnsmasq and firewall rules, which this panel doesn't manage.", "#e5c07b"));
    } else if (role === "bridge") {
      const cands = ifaces.filter(x => x.name !== i.name && x.type !== "vlan" && x.live_role !== "uplink");
      F.push(input("bridge", "br", "br0"));
      F.push(checks("members", cands.length ? cands.map(x => box(c.members.indexOf(x.name) >= 0, x.name, () => set({ members: c.members.indexOf(x.name) >= 0 ? c.members.filter(y => y !== x.name) : c.members.concat([x.name]) }))) : [{ box: "", color: "#5c6370", label: "no other ports to add", toggle: () => {}, title: "" }]));
      F.push(note("", "libvirt/qemu ports (vnet0, tap0) join a bridge themselves when a VM is started on it", "#5c6370"));
      F.push(cycle("bridge ipv4", "brIp", ["DHCP", "None (L2 only)"]));
      F.push(checks("", [box(c.stp, "spanning tree", () => set({ stp: !c.stp }))]));
    } else {
      F.push(note("", "link is set down and NetworkManager leaves it alone. Pick a role above to bring it back."));
    }

    const tabs = roleList.map(r => ({ key: r[1], label: roleLabels[r[0]], desc: r[2], active: role === r[0], color: role === r[0] ? roleColors[r[0]] : "#5c6370", pick: () => setRole(r[0]) }));
    const state = busyHere ? [spinner + " working", "#e5c07b"] : dirty ? ["● unsaved changes", "#e5c07b"]
      : i.live_role === "off" ? ["○ down", "#5c6370"] : !i.carrier ? ["○ waiting for cable", "#e5c07b"]
      : { uplink: ["● connected", "#89ca78"], share: ["◉ sharing", "#d19a66"], host: ["◉ serving", "#d55fde"], bridge: ["● bridged", "#61afef"] }[i.live_role];

    let info = [];
    const rate = rates[i.name];
    const fmtRate = b => b >= 1048576 ? (b / 1048576).toFixed(1) + " MB/s" : Math.round(b / 1024) + " KB/s";
    if (!dirty && i.carrier && i.live_role !== "off" && !busyHere) {
      const upt = i.since ? ago(i.since) : "—";
      if (i.live_role === "uplink") info = [
        { k: "ipv4", v: i.live.ip4 || "—" }, { k: "gateway", v: i.live.gw || "—" }, { k: "dns", v: i.live.dns.join(", ") || "—" },
        { k: "ipv6", v: i.live.ip6 || "off" }, { k: "link", v: (i.speed || "—") + " full" }, { k: "mac", v: i.mac },
        { k: "traffic", v: rate ? "↓ " + fmtRate(rate.rx) + " ↑ " + fmtRate(rate.tx) : "—" }, { k: "uptime", v: upt }];
      else if (i.live_role === "share") { const up = upstreamOf(i); info = [
        { k: "subnet", v: ethNet(lc.gw4) }, { k: "gateway", v: (lc.gw4 || "").split("/")[0] }, { k: "upstream", v: up.ok ? up.why : "— " + up.why }, { k: "nat", v: up.ok ? "masquerade" : "inactive" },
        { k: "traffic", v: rate ? "↓ " + fmtRate(rate.rx) + " ↑ " + fmtRate(rate.tx) : "—" }, { k: "uptime", v: upt }]; }
      else if (i.live_role === "bridge") info = [{ k: "bridge", v: lc.br }, { k: "ports", v: [i.name].concat(lc.members).join(" ") }, { k: "stp", v: "see bridge" }, { k: "uptime", v: upt }];
    }

    let jobV = null;
    if (job) {
      const j = job;
      jobV = { title: j.title, right: j.done ? "[×]" : spinner + " " + Math.min(j.i + 1, j.steps.length) + "/" + j.steps.length,
        lines: j.steps.map((st, n) => {
          const done = st.state !== "wait", cur = !done && n === j.i && !j.done;
          const col = st.state === "bad" ? "#ef596f" : st.state === "warn" ? "#e5c07b" : st.state === "ok" ? "#89ca78" : cur ? "#e5c07b" : "#404754";
          return { mark: done ? (st.state === "bad" ? "✗" : st.state === "warn" ? "!" : "✓") : cur ? spinner : "·", label: st.l, result: done ? st.r : "", color: col, textColor: done || cur ? "#abb2bf" : "#5c6370" };
        }) };
    }

    const serving = i.live_role === "share" && i.carrier && !dirty;
    const leases = i.leases.map(l => ({ name: l.name, ip: l.ip, mac: l.mac, left: l.left, online: l.online }));
    const hostRole = role === "host";

    return Object.assign(base, {
      empty: false, selName: i.name, roleColor: roleColors[role], state: state[0], stateColor: state[1],
      roleTabs: tabs, roleDesc: roleList.find(r => r[0] === role)[2], fields: F,
      applyLabel: hostRole ? "< unavailable >" : busyHere ? spinner + " applying" : dirty ? "< apply >" : "< reapply >",
      applyColor: hostRole ? "#404754" : dirty ? "#2bbac5" : "#5c6370", applyEnabled: !hostRole && !busy,
      dirty: dirty, canDelete: i.type === "vlan", hasInfo: info.length > 0, info: info,
      job: jobV, serving: serving, leases: leases, leaseCount: leases.length,
      pool: i.live_role === "share" ? ethNet(lc.gw4) + " · dhcp" : "",
      apply: () => apply(), revert: () => revert(), test: () => test(), toggleAdv: () => { be.adv = !be.adv; },
      deleteVlan: () => deleteVlan(), dismissJob: () => dismissJob(), addVlan: () => addVlan()
    });
  }
}

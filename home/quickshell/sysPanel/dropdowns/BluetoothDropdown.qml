import QtQuick
import "../.."
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../Phosphor.js" as Phosphor
import "../components"

// ===== BLUETOOTH DROPDOWN =====
// Real data/actions via Quickshell.Bluetooth (bluez), phase 3b. Phase 3a
// built this same layout on fully hardcoded state to get the design
// signed off first; this pass swaps that for the real adapter/device
// list and leaves the visual structure alone.
//
// Pairing: home/bluetooth-agent/coel_bt_agent.py (systemd user service
// bluetooth-agent) registers as BlueZ's default KeyboardDisplay agent and
// forwards every question -- compare a passkey, type a PIN/passkey, allow a
// connection -- over $XDG_RUNTIME_DIR/coel-bt-agent.sock as JSON lines (the
// protocol is documented at the top of that script). This dropdown connects
// below ("pairing agent link"), drives the staged pairing modal from those
// events, and sends the answer back. With the agent unreachable, pairing
// still works for Just Works devices (the agent auto-accepts those itself),
// the modal just never gets a passkey to show.
//
// Rows that mix several fixed-width text columns (the paired/nearby
// device lists) use manual x positioning, not RowLayout -- learned the
// hard way in PowerDropdown.qml's profile rows that RowLayout's
// constraint solver can silently produce inconsistent per-row results
// even with every column's min/maxWidth pinned equal. Manual x (each
// column's x = previous column's x + width + gap) has no constraint
// solver in the loop to disagree with.
Item {
  id: dropdownRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]

  signal closeRequested()

  // ----- real adapter state -----
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool powered: adapter !== null && adapter.enabled
  readonly property bool discoverable: adapter !== null && adapter.discoverable
  readonly property bool scanning: adapter !== null && adapter.discovering
  readonly property string adapterId: adapter !== null ? adapter.adapterId : "—"

  function togglePower() { if (adapter) adapter.enabled = !adapter.enabled; }
  function toggleDiscoverable() { if (adapter) adapter.discoverable = !adapter.discoverable; }
  function toggleScanning() { if (adapter) adapter.discovering = !adapter.discovering; }

  // BlueZ's Icon property follows the freedesktop icon-naming spec --
  // maps the handful of values real peripherals actually report to a
  // Phosphor glyph and a plain-word "kind" for the nearby list.
  function iconFor(blueIcon) {
    const map = {
      "audio-headphones": "headphones", "audio-headset": "headphones",
      "audio-card": "speaker-high", "multimedia-player": "speaker-high",
      "input-mouse": "mouse", "input-keyboard": "keyboard",
      "input-tablet": "device-mobile", "phone": "device-mobile", "computer": "device-mobile",
    };
    return map[blueIcon] || "question";
  }
  function kindFor(blueIcon) {
    const map = {
      "audio-headphones": "headphones", "audio-headset": "headset",
      "audio-card": "speaker", "multimedia-player": "speaker",
      "input-mouse": "mouse", "input-keyboard": "keyboard",
      "input-tablet": "tablet", "phone": "phone", "computer": "computer",
    };
    return map[blueIcon] || "unknown";
  }

  // Devices on the default adapter only -- Bluetooth.devices is every
  // device across every adapter Quickshell knows about.
  readonly property var adapterDevices: {
    const out = [];
    if (!adapter) return out;
    for (const d of Bluetooth.devices.values) {
      if (d.adapter === adapter) out.push(d);
    }
    return out;
  }
  readonly property var pairedDevices: adapterDevices.filter(d => d.paired).map(d => ({
    device: d,
    name: d.name || d.deviceName || d.address,
    icon: iconFor(d.icon),
    kind: kindFor(d.icon),
    connected: d.connected,
    trusted: d.trusted,
    battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1,
    address: d.address,
  }))
  // deviceName is BlueZ's own Name property -- what the device actually
  // broadcasts -- as opposed to `name`/Alias, which silently falls back
  // to the bare address when nothing real was ever broadcast. A live BLE
  // scan turns up a *lot* of that: other people's phones, earbuds cases,
  // fitness trackers, IoT junk, all advertising with no name at all.
  // Requiring a real deviceName is what actually separates "a peripheral
  // worth pairing with" from that noise, not just a cosmetic filter.
  readonly property var nearbyDevices: adapterDevices.filter(d => !d.paired && d.deviceName && d.deviceName.length > 0).map(d => ({
    device: d,
    name: d.name || d.deviceName,
    icon: iconFor(d.icon),
    kind: kindFor(d.icon),
  }))

  // "paired" or "nearby" -- which list tab/j/k apply to. `focusedList` is
  // just the last thing explicitly picked; `effectiveFocusedList` is what
  // actually drives everything (rendering, key handling) and forces
  // "nearby" whenever there's nothing paired to focus -- there's nothing
  // useful "paired" can mean with an empty list, so nothing (not tab, not
  // a stale value left over from before the last device got forgotten)
  // gets to point there while it's empty.
  property string focusedList: "paired"
  readonly property string effectiveFocusedList: (focusedList === "paired" && pairedDevices.length === 0) ? "nearby" : focusedList
  property int pairedSel: 0
  property int nearbySel: 0
  readonly property var currentPaired: pairedDevices.length > 0 ? pairedDevices[Math.min(pairedSel, pairedDevices.length - 1)] : null

  function toggleConnect(entry) {
    if (!entry) return;
    if (entry.connected) entry.device.disconnect();
    else startConnect(entry);
  }
  function toggleTrust(entry) {
    if (!entry) return;
    entry.device.trusted = !entry.device.trusted;
  }
  function forget(entry) {
    if (!entry) return;
    entry.device.forget();
  }

  // ----- pairing flow -----
  // `pair` is the modal's state, or null when it's closed:
  //   { stage, dev:{name,address,icon}, code, entered, reqId, left, deadline, reason, ours }
  // stage: request (waiting) | confirm | type | passkey | pin | authorize | done | failed
  property var pairingDevice: null          // Quickshell Device we called pair() on, if any
  property var pair: null
  property bool userCancelled: false
  readonly property bool pairingOpen: pair !== null
  signal attentionRequested()               // an agent question arrived: Panel opens this dropdown

  function setPair(patch) { pair = Object.assign({}, pair || {}, patch); }
  function devInfo(d) { return { name: d.name || d.deviceName || d.address, address: d.address, icon: d.icon || "" }; }
  function pad6(n) { return String(n).padStart(6, "0"); }

  // Pair/connect go through the agent when it is reachable (real step events and BlueZ's own error
  // text); otherwise straight through Quickshell, which only reports pairing/paired/connected.
  readonly property var pairSteps: ["reaching the device", "authenticating", "paired"]
  readonly property var connectSteps: ["reaching the device", "connecting services", "connected"]
  function sendAgent(obj) { agentSock.write(JSON.stringify(obj) + "\n"); agentSock.flush(); }
  function beginOp(mode, dev, quickshellDevice) {
    userCancelled = false;
    pairingDevice = quickshellDevice;
    const viaAgent = agentOnline && agentVersion >= 2;       // an older agent (not rebuilt yet) lacks the commands
    pair = { stage: "request", mode: mode, dev: dev, reqId: -1, left: -1, ours: true, step: 0, viaAgent: viaAgent, kind: dev.icon };
    if (viaAgent) {
      requestGuard.stop();
      sendAgent({ cmd: mode, address: dev.address });
    } else {
      requestGuard.restart();
      if (mode === "pair") quickshellDevice.pair(); else quickshellDevice.connect();
    }
  }
  function startPairing(entry) { if (entry) beginOp("pair", devInfo(entry.device), entry.device); }
  function startConnect(entry) { if (entry) beginOp("connect", devInfo(entry.device), entry.device); }
  function retryPairing() {
    if (!pair || !pairingDevice) { closePair(); return; }
    beginOp(pair.mode || "pair", pair.dev, pairingDevice);
  }
  function closePair() {
    requestGuard.stop(); doneTimer.stop();
    pair = null;
    pairingDevice = null;
    userCancelled = false;
    dropdownRoot.forceActiveFocus();
  }
  function cancelPairing() {
    if (!pair) return;
    if (pair.stage === "failed" || pair.stage === "done") { closePair(); return; }
    userCancelled = true;
    if (pair.reqId >= 0) sendReply(false, null);
    if (pair.viaAgent) sendAgent({ cmd: "cancel", address: pair.dev.address });
    else if (pairingDevice && pair.mode !== "connect") pairingDevice.cancelPair();
    closePair();
  }
  function failPair(reason) {
    if (!pair || pair.stage === "done") return;
    requestGuard.stop();
    setPair({ stage: "failed", reason: reason, reqId: -1, left: -1 });
  }
  function donePair() {
    if (!pair || pair.stage === "done") return;
    requestGuard.stop();
    setPair({ stage: "done", reqId: -1, left: -1 });
    doneTimer.restart();
  }
  Timer { id: doneTimer; interval: 1100; onTriggered: dropdownRoot.closePair() }
  // BlueZ can refuse a Pair() so fast that `pairing` never visibly flips, which would leave the
  // modal on "requesting" forever -- give up if nothing at all happened.
  Timer {
    id: requestGuard; interval: 20000
    onTriggered: if (dropdownRoot.pair && dropdownRoot.pair.stage === "request") dropdownRoot.failPair("no response from the device")
  }
  Connections {
    target: dropdownRoot.pairingDevice
    function onPairingChanged() {
      const d = dropdownRoot.pairingDevice;
      if (!d || d.pairing || !dropdownRoot.pair || dropdownRoot.pair.viaAgent) return;
      if (d.paired) dropdownRoot.donePair();
      else if (!dropdownRoot.userCancelled) dropdownRoot.failPair("pairing failed -- the device refused, timed out or went out of range");
    }
    function onPairedChanged() { if (dropdownRoot.pairingDevice && dropdownRoot.pairingDevice.paired && dropdownRoot.pair && !dropdownRoot.pair.viaAgent) dropdownRoot.donePair(); }
    function onConnectedChanged() { const p = dropdownRoot.pair; if (p && !p.viaAgent && p.mode === "connect" && dropdownRoot.pairingDevice.connected) dropdownRoot.donePair(); }
  }

  // ----- pairing agent link -----
  // Reconnects every 3s while the socket is down (agent restarting, not yet started).
  readonly property string agentSocketPath: Quickshell.env("COEL_BT_AGENT_SOCKET") || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/coel-bt-agent.sock")
  readonly property bool agentOnline: agentSock.connected
  property int agentVersion: 0
  Socket {
    id: agentSock
    path: dropdownRoot.agentSocketPath
    connected: true
    parser: SplitParser { onRead: line => dropdownRoot.onAgentLine(line) }
  }
  Timer {
    interval: 3000; repeat: true; running: !agentSock.connected
    onTriggered: { agentSock.connected = false; agentSock.connected = true; }
  }
  function sendReply(accept, value) {
    if (!pair || pair.reqId < 0) return;
    agentSock.write(JSON.stringify({ cmd: "reply", id: pair.reqId, accept: accept, value: value }) + "\n");
    agentSock.flush();
    setPair({ stage: "request", reqId: -1, left: -1, deadline: 0 });
    requestGuard.restart();
  }
  readonly property var serviceNames: ({
    "0000110b": "audio output (A2DP)", "0000110a": "audio source", "0000111e": "hands-free calls",
    "00001108": "headset calls", "00001124": "keyboard / mouse (HID)", "00001812": "keyboard / mouse (HID)",
  })
  function onAgentLine(line) {
    let m;
    try { m = JSON.parse(line); } catch (e) { return; }
    if (m.event === "hello") { agentVersion = m.version || 1; return; }
    if (m.event === "request") {
      // A question about a device we didn't start pairing with (it started it): open a modal for it.
      if (!pair || pair.dev.address !== m.device.address) pair = { stage: "request", dev: m.device, reqId: -1, left: -1, ours: false };
      const base = { dev: m.device, reqId: m.id, left: m.timeout, deadline: Date.now() + m.timeout * 1000, entered: 0 };
      if (m.kind === "confirm") setPair(Object.assign(base, { stage: "confirm", code: pad6(m.passkey) }));
      else if (m.kind === "passkey" || m.kind === "pincode") setPair(Object.assign(base, { stage: m.kind === "passkey" ? "passkey" : "pin", input: "" }));
      else setPair(Object.assign(base, { stage: "authorize", service: m.kind === "service" ? (serviceNames[String(m.uuid).slice(0, 8)] || "a service") : "" }));
      requestGuard.stop();
      if (pair.step < 1) setPair({ step: 1 });
      attentionRequested();
    } else if (m.event === "display") {
      if (!pair || pair.dev.address !== m.device.address) pair = { stage: "request", dev: m.device, reqId: -1, left: -1, ours: false };
      setPair({ stage: "type", dev: m.device, code: m.kind === "passkey" ? pad6(m.passkey) : String(m.passkey), entered: m.entered, reqId: -1, left: -1 });
      requestGuard.stop();
      attentionRequested();
    } else if (m.event === "cancel") {
      if (pair && pair.reqId === m.id) failPair(m.reason === "timeout" ? "timed out waiting for an answer" : "cancelled by the device");
    } else if (m.event === "status") {
      if (!pair || !pair.viaAgent || pair.dev.address.toUpperCase() !== String(m.address).toUpperCase() || pair.stage === "done" || pair.stage === "failed") return;
      if (m.step === "linking") setPair({ step: Math.max(pair.step, 0) });
      else if (m.step === "linked") setPair({ step: Math.max(pair.step, 1) });
      else if (m.step === "resolved") setPair({ step: Math.max(pair.step, 2) });
      else if (m.step === "done") donePair();
      else if (m.step === "failed" && !userCancelled) failPair(m.reason || "failed");
    } else if (m.event === "paired") {
      if (pair && pair.dev.address === m.device.address && m.paired) donePair();
    }
  }
  // Seconds left on a request (drives the title-bar counter and the bar).
  Timer {
    interval: 500; repeat: true; running: dropdownRoot.pair !== null && dropdownRoot.pair.deadline > 0
    onTriggered: if (dropdownRoot.pair && dropdownRoot.pair.deadline > 0) dropdownRoot.setPair({ left: Math.max(0, Math.ceil((dropdownRoot.pair.deadline - Date.now()) / 1000)) })
  }
  property int pairSpin: 0
  readonly property string pairSpinner: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[pairSpin % 10]
  Timer { interval: 80; repeat: true; running: dropdownRoot.pair !== null && dropdownRoot.pair.stage === "request"; onTriggered: dropdownRoot.pairSpin++ }

  // Keybind letter in the accent yellow, like the mockup's "[c]onnect" buttons.
  function kb(k) { return "<font color=\"" + colors[2] + "\">" + k + "</font>"; }
  focus: true
  Keys.onPressed: (event) => {
    if (pairingOpen) {
      event.accepted = true;
      const st = pair.stage, k = event.key;
      if (st === "confirm" || st === "authorize") {
        if (k === Qt.Key_Y || k === Qt.Key_Return || k === Qt.Key_Enter) sendReply(true, null);
        else if (k === Qt.Key_N || k === Qt.Key_Escape) cancelPairing();
      } else if (st === "failed") {
        if (k === Qt.Key_R) retryPairing();
        else if (k === Qt.Key_Escape) closePair();
      } else if (st === "done") {
        closePair();
      } else if (k === Qt.Key_Escape) {
        cancelPairing();
      } else if (st !== "pin" && st !== "passkey") {
        event.accepted = true;
      } else {
        event.accepted = false;      // typed digits belong to the input field
      }
      return;
    }
    event.accepted = true;
    // Only two lists, so forward/backward tabbing is the same toggle
    // either way. Checking for both Key_Tab and Key_Backtab rather than
    // a Shift-modified Key_Tab: Qt typically delivers Shift+Tab as the
    // distinct Key_Backtab code rather than Key_Tab with a modifier flag
    // set, though that can depend on the focus chain -- not independently
    // verified against this specific FocusScope setup, so this handles
    // both forms rather than assuming which one shows up.
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      // Blocked from landing on "paired" while it's empty -- there's
      // nothing there to focus, so tabbing just does nothing instead of
      // parking the cursor on an empty list.
      if (effectiveFocusedList === "paired") focusedList = "nearby";
      else if (pairedDevices.length > 0) focusedList = "paired";
      return;
    }
    switch (event.key) {
      case Qt.Key_P:
        togglePower();
        break;
      case Qt.Key_V:
        toggleDiscoverable();
        break;
      case Qt.Key_S:
        if (effectiveFocusedList === "nearby") toggleScanning();
        else event.accepted = false;
        break;
      case Qt.Key_J:
      case Qt.Key_Down:
        if (effectiveFocusedList === "paired") pairedSel = Math.min(pairedDevices.length - 1, pairedSel + 1);
        else nearbySel = Math.min(nearbyDevices.length - 1, nearbySel + 1);
        break;
      case Qt.Key_K:
      case Qt.Key_Up:
        if (effectiveFocusedList === "paired") pairedSel = Math.max(0, pairedSel - 1);
        else nearbySel = Math.max(0, nearbySel - 1);
        break;
      case Qt.Key_Return:
      case Qt.Key_Enter:
        if (effectiveFocusedList === "paired") { if (pairedDevices.length > 0) toggleConnect(pairedDevices[pairedSel]); }
        else { if (nearbyDevices.length > 0) startPairing(nearbyDevices[nearbySel]); }
        break;
      case Qt.Key_C:
        if (effectiveFocusedList === "paired" && pairedDevices.length > 0) toggleConnect(pairedDevices[pairedSel]);
        else event.accepted = false;
        break;
      case Qt.Key_T:
        if (effectiveFocusedList === "paired" && pairedDevices.length > 0) toggleTrust(pairedDevices[pairedSel]);
        else event.accepted = false;
        break;
      case Qt.Key_F:
        if (effectiveFocusedList === "paired" && pairedDevices.length > 0) forget(pairedDevices[pairedSel]);
        else event.accepted = false;
        break;
      default:
        event.accepted = false;
    }
  }

  implicitWidth: 448
  implicitHeight: Math.max(column.implicitHeight, pairingOpen ? 330 : 0)

  Column {
    id: column
    width: parent.width
    spacing: 0

    // ----- header -----
    RowLayout {
      width: parent.width
      height: 28

      RowLayout {
        spacing: 8
        Text {
          text: "bluetooth"
          color: dropdownRoot.colors[0]
          font.family: "JetBrains Mono"
          font.weight: Font.DemiBold
          font.pixelSize: 13
        }
        Text {
          text: "─ " + dropdownRoot.adapterId + " ─"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
        Text {
          text: dropdownRoot.powered ? (dropdownRoot.discoverable ? "● discoverable" : "● on") : "○ off"
          color: dropdownRoot.powered ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        implicitWidth: powerLabel.implicitWidth + 16
        implicitHeight: 20
        radius: Globals.eyeCandyOff ? 0 : 2
        color: dropdownRoot.powered ? dropdownRoot.hoverColor : "transparent"
        Text {
          id: powerLabel
          anchors.centerIn: parent
          text: "p power"
          color: dropdownRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: dropdownRoot.togglePower()
        }
      }
      Rectangle {
        implicitWidth: visLabel.implicitWidth + 16
        implicitHeight: 20
        radius: Globals.eyeCandyOff ? 0 : 2
        color: dropdownRoot.discoverable ? dropdownRoot.hoverColor : "transparent"
        Text {
          id: visLabel
          anchors.centerIn: parent
          text: "v visible"
          color: dropdownRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: dropdownRoot.toggleDiscoverable()
        }
      }
      Text {
        text: "[×]"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.PointingHandCursor
          onClicked: dropdownRoot.closeRequested()
        }
      }
    }

    // ----- powered off / no adapter state -----
    Rectangle {
      visible: !dropdownRoot.powered
      width: parent.width
      height: visible ? offColumn.implicitHeight + 36 : 0
      radius: Globals.eyeCandyOff ? 0 : 2
      color: "transparent"
      border.width: 1
      border.color: dropdownRoot.hoverColor

      Column {
        id: offColumn
        anchors.centerIn: parent
        spacing: 10
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: dropdownRoot.adapter ? "○ adapter is powered off" : "○ no bluetooth adapter found"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
        Rectangle {
          visible: dropdownRoot.adapter !== null
          anchors.horizontalCenter: parent.horizontalCenter
          implicitWidth: onLabel.implicitWidth + 20
          implicitHeight: 22
          radius: Globals.eyeCandyOff ? 0 : 2
          color: dropdownRoot.colors[0]
          Text {
            id: onLabel
            anchors.centerIn: parent
            text: "< power on >"
            color: "#282c34"
            font.family: "JetBrains Mono"
            font.weight: Font.DemiBold
            font.pixelSize: 13
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dropdownRoot.togglePower()
          }
        }
      }
    }

    // ----- paired devices + detail -----
    Section {
      visible: dropdownRoot.powered
      width: parent.width
      label: "devices (" + dropdownRoot.pairedDevices.length + ")"
      labelColor: dropdownRoot.colors[0]
      paddingTop: 10
      paddingBottom: 6
      paddingSide: 4
      spacing: 2

      Repeater {
        model: dropdownRoot.pairedDevices
        delegate: Rectangle {
          id: pRow
          required property var modelData
          required property int index
          readonly property bool sel: dropdownRoot.effectiveFocusedList === "paired" && index === dropdownRoot.pairedSel

          width: parent.width
          height: 22
          radius: Globals.eyeCandyOff ? 0 : 2
          color: sel ? "#2f343e" : (pMouse.containsMouse ? "#2f343e" : "transparent")

          MouseArea {
            id: pMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { dropdownRoot.focusedList = "paired"; dropdownRoot.pairedSel = pRow.index; }
            onDoubleClicked: dropdownRoot.toggleConnect(pRow.modelData)
          }

          Text {
            id: pMarker
            x: 8
            width: 10
            anchors.verticalCenter: parent.verticalCenter
            text: pRow.sel ? "▌" : ""
            color: dropdownRoot.colors[0]
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          Text {
            id: pIcon
            x: pMarker.x + pMarker.width + 6
            width: 16
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Phosphor.icon(pRow.modelData.icon)
            color: pRow.modelData.connected ? dropdownRoot.colors[0] : dropdownRoot.mutedColor
            font.family: "Phosphor"
            font.pixelSize: 13
          }
          Text {
            id: pBattery
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            // Fixed width (not just content-hugging) so this column's left
            // edge -- what pStatus anchors off of below -- lands at the
            // same x on every row, whether a device reports "100%", "5%"
            // or nothing at all (empty string, no battery data).
            width: 36
            horizontalAlignment: Text.AlignRight
            text: pRow.modelData.battery >= 0 ? pRow.modelData.battery + "%" : ""
            color: pRow.modelData.battery >= 0 && pRow.modelData.battery <= 20 ? dropdownRoot.colors[1] : dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          Text {
            id: pStatus
            anchors.right: pBattery.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            // Same reasoning as pBattery's width above -- "connected" and
            // "paired" are different lengths, so without a fixed width
            // this column's own left edge (and the name column's width,
            // which is measured off it) would still drift per row even
            // with pBattery's column now fixed.
            width: 76
            horizontalAlignment: Text.AlignRight
            text: pRow.modelData.connected ? "connected" : "paired"
            color: pRow.modelData.connected ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          Text {
            x: pIcon.x + pIcon.width + 6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, pStatus.x - x - 10)
            elide: Text.ElideRight
            text: pRow.modelData.name
            color: dropdownRoot.fgColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
        }
      }

      Text {
        visible: dropdownRoot.powered && dropdownRoot.pairedDevices.length === 0
        x: 8
        text: "no paired devices"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }

      // ----- selected paired device detail -----
      // Just address/trusted/type/battery -- that's everything
      // Quickshell.Bluetooth actually exposes per device. The original
      // mock also had "profile" (A2DP/HID/...) and "signal" (dBm) rows;
      // neither has a real data source here (no UUID/RSSI properties on
      // BluetoothDevice), so rather than show two rows that would always
      // read "—", they're just not there.
      Item {
        width: parent.width
        visible: dropdownRoot.currentPaired !== null
        height: visible ? detailCol.implicitHeight + 10 : 0

        Rectangle {
          width: parent.width
          y: 0
          height: 1
          color: dropdownRoot.hoverColor
        }

        Column {
          id: detailCol
          y: 10
          x: 6
          width: parent.width - 12
          spacing: 8

          RowLayout {
            width: parent.width
            spacing: 24
            Column {
              spacing: 1
              Repeater {
                model: dropdownRoot.currentPaired ? [
                  { k: "address", v: dropdownRoot.currentPaired.address },
                  { k: "trusted", v: dropdownRoot.currentPaired.trusted ? "yes" : "no", c: dropdownRoot.currentPaired.trusted ? dropdownRoot.colors[3] : dropdownRoot.mutedColor },
                ] : []
                delegate: RowLayout {
                  required property var modelData
                  spacing: 6
                  Text { Layout.preferredWidth: 64; text: modelData.k; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                  Text { text: modelData.v; color: modelData.c || dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                }
              }
            }
            Column {
              spacing: 1
              Repeater {
                model: dropdownRoot.currentPaired ? [
                  { k: "type", v: dropdownRoot.currentPaired.kind },
                  { k: "battery", v: dropdownRoot.currentPaired.battery >= 0 ? dropdownRoot.currentPaired.battery + "%" : "—" },
                ] : []
                delegate: RowLayout {
                  required property var modelData
                  spacing: 6
                  Text { Layout.preferredWidth: 64; text: modelData.k; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                  Text { text: modelData.v; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                }
              }
            }
          }

          Row {
            spacing: 2
            Rectangle {
              implicitWidth: toggleLabel.implicitWidth + 12
              implicitHeight: 20
              radius: Globals.eyeCandyOff ? 0 : 2
              color: toggleMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text {
                id: toggleLabel
                anchors.centerIn: parent
                textFormat: Text.StyledText
                text: "[" + dropdownRoot.kb("c") + "]" + (dropdownRoot.currentPaired && dropdownRoot.currentPaired.connected ? "disconnect" : "connect")
                color: dropdownRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
              MouseArea { id: toggleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.toggleConnect(dropdownRoot.currentPaired) }
            }
            Rectangle {
              implicitWidth: trustLabel.implicitWidth + 12
              implicitHeight: 20
              radius: Globals.eyeCandyOff ? 0 : 2
              color: trustMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text {
                id: trustLabel
                anchors.centerIn: parent
                textFormat: Text.StyledText
                text: "[" + dropdownRoot.kb("t") + "]" + (dropdownRoot.currentPaired && dropdownRoot.currentPaired.trusted ? "untrust" : "trust")
                color: dropdownRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
              MouseArea { id: trustMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.toggleTrust(dropdownRoot.currentPaired) }
            }
            Rectangle {
              implicitWidth: forgetLabel.implicitWidth + 12
              implicitHeight: 20
              radius: Globals.eyeCandyOff ? 0 : 2
              color: forgetMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text {
                id: forgetLabel
                anchors.centerIn: parent
                textFormat: Text.StyledText
                text: "[" + dropdownRoot.kb("f") + "]orget"
                color: dropdownRoot.colors[1]
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
              MouseArea { id: forgetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.forget(dropdownRoot.currentPaired) }
            }
          }
        }
      }
    }

    Item { visible: dropdownRoot.powered; width: 1; height: 16 }

    // ----- nearby devices -----
    // No RSSI/signal-strength property on BluetoothDevice, so unlike the
    // phase-3a mock this can't show real signal bars -- dropped rather
    // than faked. Discovery only actually finds anything while
    // dropdownRoot.scanning (adapter.discovering) is on.
    Section {
      visible: dropdownRoot.powered
      width: parent.width
      label: "nearby (" + dropdownRoot.nearbyDevices.length + ")"
      labelColor: dropdownRoot.colors[0]
      paddingTop: 10
      paddingBottom: 6
      paddingSide: 4
      spacing: 2

      rightContent: Text {
        textFormat: Text.StyledText
        text: dropdownRoot.scanning ? ("[" + dropdownRoot.kb("s") + "]top") : ("[" + dropdownRoot.kb("s") + "]can")
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 12
      }

      Repeater {
        model: dropdownRoot.nearbyDevices
        delegate: Rectangle {
          id: nRow
          required property var modelData
          required property int index
          readonly property bool sel: dropdownRoot.effectiveFocusedList === "nearby" && index === dropdownRoot.nearbySel

          width: parent.width
          height: 22
          radius: Globals.eyeCandyOff ? 0 : 2
          color: sel ? "#2f343e" : (nMouse.containsMouse ? "#2f343e" : "transparent")

          MouseArea {
            id: nMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { dropdownRoot.focusedList = "nearby"; dropdownRoot.nearbySel = nRow.index; }
            onDoubleClicked: dropdownRoot.startPairing(nRow.modelData)
          }

          Text {
            id: nMarker
            x: 8
            width: 10
            anchors.verticalCenter: parent.verticalCenter
            text: nRow.sel ? "▌" : ""
            color: dropdownRoot.colors[0]
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          Text {
            id: nIcon
            x: nMarker.x + nMarker.width + 6
            width: 16
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Phosphor.icon(nRow.modelData.icon)
            color: dropdownRoot.mutedColor
            font.family: "Phosphor"
            font.pixelSize: 13
          }
          Rectangle {
            id: nPairBtn
            visible: nRow.sel
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: nPairLabel.implicitWidth + 10
            implicitHeight: 18
            radius: Globals.eyeCandyOff ? 0 : 2
            color: nPairMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
            Text {
              id: nPairLabel
              anchors.centerIn: parent
              text: "[pair]"
              color: dropdownRoot.colors[3]
              font.family: "JetBrains Mono"
              font.pixelSize: 12
            }
            MouseArea { id: nPairMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.startPairing(nRow.modelData) }
          }
          Text {
            id: nKind
            anchors.right: nRow.sel ? nPairBtn.left : parent.right
            anchors.rightMargin: nRow.sel ? 10 : 8
            anchors.verticalCenter: parent.verticalCenter
            text: nRow.modelData.kind
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          Text {
            x: nIcon.x + nIcon.width + 6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, nKind.x - x - 10)
            elide: Text.ElideRight
            text: nRow.modelData.name
            color: nRow.sel ? dropdownRoot.fgColor : dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
        }
      }

      Text {
        visible: dropdownRoot.powered && dropdownRoot.nearbyDevices.length === 0
        x: 8
        textFormat: Text.StyledText
        text: dropdownRoot.scanning ? "scanning…" : ("nothing found -- [" + dropdownRoot.kb("s") + "]can to look again")
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }
    }

    Item { width: 1; height: 12 }

    // ----- hints -----
    Flow {
      width: parent.width
      spacing: 14
      readonly property var hints: !dropdownRoot.powered
        ? (dropdownRoot.adapter ? [{ k: "p", l: "power on" }, { k: "esc", l: "close" }] : [{ k: "esc", l: "close" }])
        : dropdownRoot.effectiveFocusedList === "paired"
          ? [{ k: "tab", l: "nearby" }, { k: "j/k", l: "move" }, { k: "⏎/c", l: "connect" }, { k: "t", l: "trust" }, { k: "f", l: "forget" }, { k: "esc", l: "close" }]
          : [{ k: "tab", l: "devices" }, { k: "j/k", l: "move" }, { k: "⏎", l: "pair" }, { k: "s", l: "scan" }, { k: "esc", l: "close" }]
      Repeater {
        model: parent.hints
        RowLayout {
          required property var modelData
          spacing: 4
          Text { text: modelData.k; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          Text { text: modelData.l; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        }
      }
    }
  }

  // ----- pairing modal -----
  // Staged like the mockup's: request -> confirm / type / passkey / pin / authorize -> done | failed.
  // Border + legend colour follow the stage (yellow asking, green done, red failed).
  Item {
    id: pairModal
    visible: dropdownRoot.pairingOpen
    anchors.fill: parent
    readonly property var p: dropdownRoot.pair || ({ stage: "request", dev: { name: "", address: "", icon: "" }, left: -1, entered: 0, code: "" })
    readonly property string st: p.stage
    readonly property bool isConnect: p.mode === "connect"
    readonly property bool checklist: st === "request" && !!p.viaAgent
    readonly property var stepLabels: isConnect ? dropdownRoot.connectSteps : dropdownRoot.pairSteps
    property int spin: 0
    Timer { interval: 80; repeat: true; running: pairModal.visible && pairModal.checklist; onTriggered: pairModal.spin++ }
    readonly property string spinner: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[spin % 10]
    readonly property color accent: st === "failed" ? dropdownRoot.colors[1] : st === "done" ? dropdownRoot.colors[3] : dropdownRoot.colors[2]
    readonly property bool showCode: st === "confirm" || st === "type"
    readonly property bool typed: st === "pin" || st === "passkey"
    readonly property bool counting: p.left >= 0 && (st === "confirm" || st === "authorize" || typed)
    readonly property string message: st === "request" ? dropdownRoot.pairSpinner + " requesting pairing…"
      : st === "confirm" ? "Check that this passkey is shown on the device, then confirm on both sides."
      : st === "type" ? (p.entered > 0 ? "Receiving keystrokes… " + p.entered + "/" + p.code.length : "Type this code on " + p.dev.name + ", then press Enter on it.")
      : st === "passkey" ? "Enter the passkey shown on " + p.dev.name + "."
      : st === "pin" ? "Enter the PIN for " + p.dev.name + " (often 0000 or 1234)."
      : st === "authorize" ? p.dev.name + " wants to connect" + (p.service ? " (" + p.service + ")" : "") + ". Allow it?"
      : st === "done" ? (isConnect ? "✓ connected to " + p.dev.name : "✓ paired with " + p.dev.name)
      : "✗ " + (p.reason || "pairing failed")
    readonly property color messageColor: st === "request" ? dropdownRoot.colors[2] : st === "done" ? dropdownRoot.colors[3] : st === "failed" ? dropdownRoot.colors[1] : dropdownRoot.fgColor
    onTypedChanged: if (typed) Qt.callLater(() => pairInput.forceActiveFocus())

    Rectangle { anchors.fill: parent; color: "#1e2127"; opacity: 0.82 }
    MouseArea { anchors.fill: parent }

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(360, parent.width - 32)
      height: modalCol.implicitHeight + 28
      color: "#282c34"
      radius: Globals.eyeCandyOff ? 0 : 2
      border.width: 1
      border.color: pairModal.accent

      Text {
        x: 8; y: -9; leftPadding: 6; rightPadding: 6
        text: pairModal.isConnect ? (pairModal.st === "failed" ? "✗ connection failed" : pairModal.st === "done" ? "✓ connected" : "connecting")
          : pairModal.st === "failed" ? "✗ pairing failed" : pairModal.st === "done" ? "✓ paired" : pairModal.st === "authorize" ? "⚠ connection request" : (pairModal.st === "request" && pairModal.p.viaAgent) ? "pairing" : "⚠ pairing request"
        color: pairModal.accent
        font.family: "JetBrains Mono"; font.pixelSize: 13
        Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
      }
      Text {
        visible: pairModal.counting
        anchors.right: parent.right; anchors.rightMargin: 8; y: -9; leftPadding: 6; rightPadding: 6
        text: pairModal.p.left + "s"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"; font.pixelSize: 13
        Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
      }

      Column {
        id: modalCol
        x: 16; y: 14
        width: parent.width - 32
        spacing: 10

        RowLayout {
          spacing: 8
          Text { text: Phosphor.icon(dropdownRoot.iconFor(pairModal.p.dev.icon)); color: dropdownRoot.fgColor; font.family: "Phosphor"; font.pixelSize: 16 }
          Text { text: pairModal.p.dev.name; color: dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
          Text { text: pairModal.p.dev.address; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
        }

        // step checklist (agent-driven): same markers as the wi-fi connect card
        Column {
          visible: pairModal.checklist
          width: parent.width
          spacing: 2
          Repeater {
            model: pairModal.stepLabels
            delegate: RowLayout {
              required property string modelData
              required property int index
              readonly property bool done: index < pairModal.p.step
              readonly property bool cur: index === pairModal.p.step
              width: parent.width
              spacing: 8
              Text {
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
                text: parent.done ? "✓" : parent.cur ? pairModal.spinner : "○"
                color: parent.done ? dropdownRoot.colors[3] : parent.cur ? dropdownRoot.colors[2] : dropdownRoot.mutedColor
                font.family: "JetBrains Mono"; font.pixelSize: parent.cur ? 15 : 13
                font.weight: parent.done || parent.cur ? Font.Bold : Font.Normal
              }
              Text {
                Layout.fillWidth: true
                text: parent.modelData
                color: parent.done ? "#7f848e" : parent.cur ? dropdownRoot.fgColor : dropdownRoot.mutedColor
                font.family: "JetBrains Mono"; font.pixelSize: 13
              }
            }
          }
        }
        Text {
          visible: pairModal.checklist && !pairModal.isConnect && (pairModal.p.kind === "phone" || pairModal.p.kind === "computer")
          width: parent.width
          wrapMode: Text.WordWrap
          text: "On the other device, open its Bluetooth settings and keep that screen open -- phones only accept new pairings while it is showing."
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"; font.pixelSize: 12
        }

        Text {
          visible: !pairModal.checklist
          width: parent.width
          wrapMode: Text.WordWrap
          text: pairModal.message
          color: pairModal.messageColor
          font.family: "JetBrains Mono"; font.pixelSize: 13
        }

        // the code, one box per digit, a gap after the third (6-digit passkeys)
        Row {
          visible: pairModal.showCode
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 6
          Repeater {
            model: pairModal.p.code ? pairModal.p.code.split("") : []
            delegate: Rectangle {
              required property string modelData
              required property int index
              readonly property bool typedDigit: pairModal.st === "type" && index < pairModal.p.entered
              width: 30; height: 38
              radius: Globals.eyeCandyOff ? 0 : 2
              color: "transparent"
              border.width: 1
              border.color: typedDigit ? dropdownRoot.colors[3] : dropdownRoot.hoverColor
              Text {
                anchors.centerIn: parent
                text: parent.modelData
                color: parent.typedDigit ? dropdownRoot.colors[3] : dropdownRoot.colors[2]
                font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: 22
              }
              // extra gap after the third digit of a 6-digit code
              Item { width: parent.index === 2 && pairModal.p.code.length === 6 ? 10 : 0; height: 1; anchors.left: parent.right }
            }
          }
        }

        // remaining time as a block bar, red when nearly out
        Text {
          visible: pairModal.counting && !pairModal.typed
          anchors.horizontalCenter: parent.horizontalCenter
          readonly property int on: Math.round(Math.max(0, pairModal.p.left) / Math.max(1, pairModal.p.deadline ? 30 : 30) * 10)
          text: "█".repeat(Math.min(10, on)) + "░".repeat(10 - Math.min(10, on))
          color: pairModal.p.left <= 8 ? dropdownRoot.colors[1] : dropdownRoot.mutedColor
          font.family: "JetBrains Mono"; font.pixelSize: 13
        }

        // PIN / passkey entry
        Rectangle {
          visible: pairModal.typed
          width: parent.width
          implicitHeight: 28
          color: "#1e2127"
          radius: Globals.eyeCandyOff ? 0 : 2
          border.width: 1
          border.color: pairInput.activeFocus ? dropdownRoot.colors[2] : dropdownRoot.hoverColor
          TextInput {
            id: pairInput
            anchors.fill: parent; anchors.margins: 6
            color: dropdownRoot.fgColor
            font.family: "JetBrains Mono"; font.pixelSize: 15; font.letterSpacing: 3
            inputMethodHints: pairModal.st === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
            maximumLength: pairModal.st === "passkey" ? 6 : 16
            onAccepted: if (text.length > 0) { dropdownRoot.sendReply(true, text); text = ""; }
            Keys.onEscapePressed: dropdownRoot.cancelPairing()
          }
        }

        Row {
          spacing: 8
          Rectangle {
            visible: pairModal.st === "confirm" || pairModal.st === "authorize"
            implicitWidth: yesLabel.implicitWidth + 20; implicitHeight: 22
            radius: Globals.eyeCandyOff ? 0 : 2
            color: yesMouse.containsMouse ? dropdownRoot.fgColor : dropdownRoot.colors[3]
            Text { id: yesLabel; anchors.centerIn: parent; text: pairModal.st === "confirm" ? "< y codes match >" : "< y allow >"; color: "#282c34"; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: 13 }
            MouseArea { id: yesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.sendReply(true, null) }
          }
          Rectangle {
            visible: pairModal.typed
            implicitWidth: submitLabel.implicitWidth + 20; implicitHeight: 22
            radius: Globals.eyeCandyOff ? 0 : 2
            color: submitMouse.containsMouse ? dropdownRoot.fgColor : dropdownRoot.colors[0]
            Text { id: submitLabel; anchors.centerIn: parent; text: "< ⏎ submit >"; color: "#282c34"; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: 13 }
            MouseArea { id: submitMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pairInput.accepted() }
          }
          Rectangle {
            visible: pairModal.st === "failed"
            implicitWidth: retryLabel.implicitWidth + 20; implicitHeight: 22
            radius: Globals.eyeCandyOff ? 0 : 2
            color: retryMouse.containsMouse ? dropdownRoot.fgColor : dropdownRoot.colors[0]
            Text { id: retryLabel; anchors.centerIn: parent; text: "< r retry >"; color: "#282c34"; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: 13 }
            MouseArea { id: retryMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.retryPairing() }
          }
          Rectangle {
            visible: pairModal.st !== "done"
            implicitWidth: cancelLabel.implicitWidth + 20; implicitHeight: 22
            radius: Globals.eyeCandyOff ? 0 : 2
            color: cancelMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
            Text {
              id: cancelLabel
              anchors.centerIn: parent
              text: pairModal.st === "failed" ? "< esc dismiss >" : (pairModal.st === "confirm" || pairModal.st === "authorize") ? "< n reject >" : "< esc cancel >"
              color: dropdownRoot.colors[1]
              font.family: "JetBrains Mono"; font.pixelSize: 13
            }
            MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.cancelPairing() }
          }
        }
      }
    }
  }
}

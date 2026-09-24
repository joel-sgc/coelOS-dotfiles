import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "./Phosphor.js" as Phosphor

// ===== BLUETOOTH DROPDOWN =====
// Real data/actions via Quickshell.Bluetooth (bluez), phase 3b. Phase 3a
// built this same layout on fully hardcoded state to get the design
// signed off first; this pass swaps that for the real adapter/device
// list and leaves the visual structure alone.
//
// TODO(bluetooth pairing UI): no real PIN/passkey confirmation flow yet
// -- left as-is deliberately, noted here to pick back up later rather
// than build now. Current state:
//   - home/bluetooth-agent.nix registers a NoInputNoOutput bluetoothctl
//     agent for the session, which is *enough* for "Just Works" SSP
//     pairing (most consumer headphones/speakers/mice/keyboards) --
//     that's what was actually broken before and is now fixed.
//   - Devices that require real Numeric Comparison (both sides show a
//     6-digit code, human confirms they match) or Passkey/PIN entry
//     still can't pair: a NoInputNoOutput agent has no I/O capability to
//     satisfy that, by definition, so BlueZ can't ask it. The pairing
//     modal below reflects that honestly -- a live "pairing…" status
//     plus cancel, not a fabricated confirmation code -- rather than
//     pretend this is handled.
// The real fix needs an actual org.bluez.Agent1 implementation with a
// real capability (DisplayYesNo or KeyboardDisplay), which Quickshell
// itself can't provide -- checked its QML modules for a general D-Bus
// *service*-export API (as opposed to the client-side bindings it does
// have for bluez/UPower/etc): there isn't one. That means this needs a
// small companion process (e.g. Python+dbus / a compiled helper)
// registered as the agent, bridged back to this UI somehow (a socket or
// FileView-watched state file this dropdown reads the live passkey from
// and writes the user's confirm/reject decision back to) -- a genuinely
// new piece, not a tweak to what's here.
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
    else entry.device.connect();
  }
  function toggleTrust(entry) {
    if (!entry) return;
    entry.device.trusted = !entry.device.trusted;
  }
  function forget(entry) {
    if (!entry) return;
    entry.device.forget();
  }

  // ----- pairing flow (see header comment: no real PIN/passkey agent) -----
  property var pairingDevice: null
  readonly property bool pairingOpen: pairingDevice !== null && pairingDevice.pairing
  function startPairing(entry) {
    if (!entry) return;
    pairingDevice = entry.device;
    entry.device.pair();
  }
  function cancelPairing() {
    if (pairingDevice) pairingDevice.cancelPair();
    pairingDevice = null;
  }

  focus: true
  Keys.onPressed: (event) => {
    if (pairingOpen) {
      event.accepted = true;
      if (event.key === Qt.Key_Escape) cancelPairing();
      else event.accepted = false;
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
  implicitHeight: column.implicitHeight

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
        radius: 2
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
        radius: 2
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
      radius: 2
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
          radius: 2
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
          radius: 2
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
                  Text { text: modelData.k; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
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
                  Text { text: modelData.k; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
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
              radius: 2
              color: toggleMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text {
                id: toggleLabel
                anchors.centerIn: parent
                text: "[c]" + (dropdownRoot.currentPaired && dropdownRoot.currentPaired.connected ? "disconnect" : "connect")
                color: dropdownRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
              MouseArea { id: toggleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.toggleConnect(dropdownRoot.currentPaired) }
            }
            Rectangle {
              implicitWidth: trustLabel.implicitWidth + 12
              implicitHeight: 20
              radius: 2
              color: trustMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text {
                id: trustLabel
                anchors.centerIn: parent
                text: "[t]" + (dropdownRoot.currentPaired && dropdownRoot.currentPaired.trusted ? "untrust" : "trust")
                color: dropdownRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
              MouseArea { id: trustMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.toggleTrust(dropdownRoot.currentPaired) }
            }
            Rectangle {
              implicitWidth: forgetLabel.implicitWidth + 12
              implicitHeight: 20
              radius: 2
              color: forgetMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
              Text {
                id: forgetLabel
                anchors.centerIn: parent
                text: "[f]orget"
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
        text: dropdownRoot.scanning ? "[s]top" : "[s]can"
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
          radius: 2
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
            radius: 2
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
        text: dropdownRoot.scanning ? "scanning…" : "nothing found -- [s]can to look again"
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
  // Deliberately just a live status + cancel, not a fake confirmation
  // code -- see the header comment on why a real PIN/passkey flow isn't
  // implemented yet.
  Item {
    visible: dropdownRoot.pairingOpen
    anchors.fill: parent

    Rectangle {
      anchors.fill: parent
      color: "#1e2127"
      opacity: 0.82
    }

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(320, parent.width - 32)
      height: modalCol.implicitHeight + 28
      color: "#282c34"
      radius: 2
      border.width: 1
      border.color: dropdownRoot.colors[2]

      Text {
        x: 8
        y: -9
        leftPadding: 6
        rightPadding: 6
        text: "pairing"
        color: dropdownRoot.colors[2]
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
      }

      Column {
        id: modalCol
        x: 16
        y: 14
        width: parent.width - 32
        spacing: 10

        RowLayout {
          spacing: 8
          Text {
            text: Phosphor.icon("bluetooth")
            color: dropdownRoot.fgColor
            font.family: "Phosphor"
            font.pixelSize: 15
          }
          Text {
            text: dropdownRoot.pairingDevice ? (dropdownRoot.pairingDevice.name || dropdownRoot.pairingDevice.address) : ""
            color: dropdownRoot.fgColor
            font.family: "JetBrains Mono"
            font.weight: Font.DemiBold
            font.pixelSize: 13
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "pairing… the device may prompt you to confirm a code itself."
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }

        Rectangle {
          implicitWidth: cancelLabel.implicitWidth + 20
          implicitHeight: 22
          radius: 2
          color: cancelMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
          Text {
            id: cancelLabel
            anchors.centerIn: parent
            text: "< esc cancel >"
            color: dropdownRoot.colors[1]
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.cancelPairing() }
        }
      }
    }
  }
}

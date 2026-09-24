import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "./Phosphor.js" as Phosphor

// ===== POWER DROPDOWN =====
// Battery detail, power-profile switch, brightness and session actions --
// what coel-power-profiles-menu used to cover (profile switching only),
// now inline and with real battery/brightness data alongside it.
//
// Where this deliberately doesn't match the design mock, because the mock
// was demo data and this is real hardware:
//  - No charge-limit control. Checked for it directly: no
//    charge_control_end_threshold/charge_stop_threshold sysfs file exists
//    on this battery, and no ectool/framework-tool is installed to ask
//    the EC directly either (the cros_charge_control kernel module is
//    loaded, but isn't bound to anything here -- see BAT1's own sysfs
//    dir, which carries none of its files). Nothing to wire up right now;
//    installing framework-tool is a real option if this matters enough to
//    revisit, just not something to add as a side effect of a styling
//    fix.
//  - No "ac" toggle. Whether the adapter is connected is real hardware
//    state (UPower.onBattery), not something a button here should be
//    able to override -- the mock's `a` toggle only existed because it
//    was simulating a laptop, not reading one.
//  - Only the *currently active* profile's row shows an estimated time
//    remaining. The mock fabricates a plausible-looking number for the
//    other two by assuming a fixed draw per profile; we don't have a real
//    number for "how long would the battery last on a profile we're not
//    running," and making one up would look exactly as authoritative as
//    the real figure next to it.
Item {
  id: dropdownRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]

  signal closeRequested()

  readonly property var device: UPower.displayDevice
  readonly property bool ready: device.ready
  readonly property int pct: ready ? Math.round(device.percentage * 100) : 0
  readonly property bool charging: ready && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
  readonly property bool discharging: ready && (device.state === UPowerDeviceState.Discharging || device.state === UPowerDeviceState.PendingDischarge)
  // UPower's change-rate is a magnitude in watts, not signed -- direction
  // comes from `state` separately, so this is what actually gives the
  // sparkline/rate-row their sign (+charging/-discharging/0 idle-on-AC).
  readonly property real signedRate: charging ? device.changeRate : discharging ? -device.changeRate : 0
  // batteryName is declared further down, alongside the rest of the
  // upower-CLI-derived fields it's now sourced from (device.nativePath is
  // empty -- displayDevice is a synthetic aggregate, not a real device).

  function hm(hours) {
    const m = Math.max(0, Math.round(hours * 60));
    return Math.floor(m / 60) + "h " + String(m % 60).padStart(2, "0") + "m";
  }

  readonly property string etaText: {
    if (!ready) return "";
    if (charging) {
      if (device.timeToFull > 0) return "full in " + hm(device.timeToFull / 3600);
      return "charging";
    }
    if (discharging) {
      if (device.timeToEmpty > 0) return hm(device.timeToEmpty / 3600) + " remaining";
      return "discharging";
    }
    return "on hold";
  }
  readonly property color etaColor: charging ? colors[3] : fgColor

  readonly property color levelColor: pct <= 15 ? colors[1] : pct <= 30 ? colors[2] : colors[3]
  readonly property int litCells: Math.round(pct / 5)

  // ----- battery info grid: model/voltage/cycles/health/design capacity -----
  // None of these come from UPower.displayDevice: it's a synthetic
  // aggregate device UPower synthesizes for "whatever should represent
  // battery state in a UI" (confirmed live -- its nativePath, model and
  // healthSupported are empty/false even though the real battery reports
  // all of this fine), not a handle on the real battery. UPower.devices
  // (the real device list) is also confirmed live to just never populate
  // through Quickshell's binding here, for reasons this session couldn't
  // pin down. `upower -i` on the real per-device DBus path -- found via
  // `upower -e` rather than a hardcoded BAT0/BAT1, so this keeps working
  // whatever the battery happens to be named -- gives every one of these
  // directly, so that's what this polls instead. Static-ish data (voltage
  // and health drift slowly), so 30s is plenty; percentage/rate/eta above
  // stay on UPower.displayDevice's live DBus signals, no polling lag.
  property var batteryDetails: ({})
  function parseUpowerInfo(text) {
    const result = {};
    for (const line of text.split("\n")) {
      const m = line.match(/^\s*([a-z][a-z -]*[a-z]):\s+(.+?)\s*$/i);
      if (m) result[m[1]] = m[2];
    }
    return result;
  }
  Process {
    id: batteryInfoProc
    command: [
      "sh", "-c",
      "p=$(upower -e 2>/dev/null | grep '/battery_' | head -1); [ -n \"$p\" ] && upower -i \"$p\" 2>/dev/null"
    ]
    stdout: StdioCollector {
      onStreamFinished: dropdownRoot.batteryDetails = dropdownRoot.parseUpowerInfo(text)
    }
  }
  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: batteryInfoProc.running = true
  }

  readonly property string batteryName: batteryDetails["native-path"] || "battery"
  readonly property real voltage: parseFloat(batteryDetails["voltage"]) || 0
  readonly property int cycleCount: parseInt(batteryDetails["charge-cycles"]) || 0
  readonly property real healthPct: parseFloat(batteryDetails["capacity"]) || 0
  readonly property real designCapacity: parseFloat(batteryDetails["energy-full-design"]) || 0
  readonly property string batteryModel: (batteryDetails["model"] || "").trim()

  readonly property var infoRows: [
    { k: "energy", v: ready ? device.energy.toFixed(1) + " / " + device.energyCapacity.toFixed(1) + " Wh" : "—" },
    { k: "health", v: healthPct > 0 ? healthPct.toFixed(1) + "%" : "—" },
    { k: "voltage", v: voltage > 0 ? voltage.toFixed(2) + " V" : "—" },
    { k: "cycles", v: cycleCount > 0 ? String(cycleCount) : "—" },
    { k: "design", v: designCapacity > 0 ? designCapacity.toFixed(1) + " Wh" : "—" },
    { k: "model", v: batteryModel.length > 0 ? batteryModel : "—" },
  ]

  // ----- 60s power draw sparkline -----
  property var rateHistory: []
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      const next = dropdownRoot.rateHistory.concat([dropdownRoot.signedRate]);
      if (next.length > 60) next.shift();
      dropdownRoot.rateHistory = next;
    }
  }
  readonly property real rateAvg: rateHistory.length > 0
    ? rateHistory.reduce((a, v) => a + Math.abs(v), 0) / rateHistory.length
    : 0
  readonly property real rateMax: Math.max.apply(null, rateHistory.map(v => Math.abs(v)).concat([1]))

  // ----- power profile -----
  readonly property var profileOrder: [
    { id: "performance", enumVal: PowerProfile.Performance, icon: "lightning", desc: "max boost, fans audible", colorIdx: 1 },
    { id: "balanced", enumVal: PowerProfile.Balanced, icon: "scales", desc: "default", colorIdx: 0 },
    { id: "power-saver", enumVal: PowerProfile.PowerSaver, icon: "leaf", desc: "caps boost, dims panel", colorIdx: 3 },
  ]
  readonly property var visibleProfiles: PowerProfiles.hasPerformanceProfile
    ? profileOrder
    : profileOrder.filter(p => p.id !== "performance")
  function activeProfileIndex() {
    for (let i = 0; i < visibleProfiles.length; i++) {
      if (visibleProfiles[i].enumVal === PowerProfiles.profile) return i;
    }
    return 0;
  }
  property int pwrSel: 0
  Component.onCompleted: pwrSel = activeProfileIndex()

  // ----- brightness -----
  // amdgpu_bl1 is this machine's one backlight device (checked live: only
  // entry under /sys/class/backlight). Reading straight from sysfs rather
  // than shelling out keeps the slider reactive (watchChanges); writing
  // straight to sysfs too (already confirmed group-writable via swayosd's
  // udev rule -- see configuration.nix) rather than through
  // swayosd-client, since that would pop swayosd's own OSD over this
  // popup on every drag update, on top of the slider already shown here.
  readonly property string backlightDevice: "/sys/class/backlight/amdgpu_bl1"
  FileView {
    id: brightnessFile
    path: dropdownRoot.backlightDevice + "/brightness"
    watchChanges: true
    onFileChanged: reload()
    // Both required for the write side to actually take effect, not just
    // reflect the current value: FileView blocks writes by default
    // (blockWrites), and even unblocked, its default write strategy is
    // write-to-a-temp-file-then-rename-over-the-target (atomicWrites) --
    // sysfs pseudo-files don't support creating a second file next to
    // them for that rename, so an atomic write there fails silently. This
    // was the whole reason the slider dragged fine but never actually
    // changed the backlight.
    blockWrites: false
    atomicWrites: false
  }
  FileView {
    id: maxBrightnessFile
    path: dropdownRoot.backlightDevice + "/max_brightness"
  }
  readonly property int maxBrightness: parseInt(maxBrightnessFile.text()) || 0
  readonly property int brightnessPct: maxBrightness > 0
    ? Math.round((parseInt(brightnessFile.text()) || 0) / maxBrightness * 100)
    : 0
  function setBrightness(pct) {
    if (maxBrightness <= 0) return;
    const clamped = Math.max(1, Math.min(100, pct));
    brightnessFile.setText(String(Math.round(clamped / 100 * maxBrightness)));
  }
  function nudgeBrightness(delta) {
    setBrightness(Math.round(brightnessPct / 5) * 5 + delta);
  }

  // ----- session actions -----
  readonly property var sessionActions: [
    { id: "lock", icon: "lock", label: "lock", command: ["hyprlock"] },
    { id: "suspend", icon: "moon", label: "suspend", command: ["systemctl", "suspend"] },
    { id: "hibernate", icon: "snowflake", label: "hibernate", command: ["systemctl", "hibernate"] },
    { id: "reboot", icon: "arrow-clockwise", label: "reboot", command: ["systemctl", "reboot"] },
    { id: "poweroff", icon: "power", label: "shut down", command: ["systemctl", "poweroff"] },
  ]
  property string armedAction: ""
  property string sessionMessage: ""
  Timer {
    id: armTimer
    interval: 3000
    onTriggered: dropdownRoot.armedAction = ""
  }
  function runSessionAction(action) {
    if (action.id !== "lock" && armedAction !== action.id) {
      armedAction = action.id;
      sessionMessage = "click again to confirm";
      armTimer.restart();
      return;
    }
    armTimer.stop();
    armedAction = "";
    sessionMessage = "→ " + action.command.join(" ");
    Quickshell.execDetached(action.command);
  }

  focus: true
  Keys.onPressed: (event) => {
    event.accepted = true;
    switch (event.key) {
      case Qt.Key_1:
      case Qt.Key_2:
      case Qt.Key_3: {
        const i = event.key - Qt.Key_1;
        if (i < visibleProfiles.length) {
          pwrSel = i;
          PowerProfiles.profile = visibleProfiles[i].enumVal;
        }
        break;
      }
      case Qt.Key_J:
      case Qt.Key_Down:
        pwrSel = Math.min(visibleProfiles.length - 1, pwrSel + 1);
        break;
      case Qt.Key_K:
      case Qt.Key_Up:
        pwrSel = Math.max(0, pwrSel - 1);
        break;
      case Qt.Key_Return:
      case Qt.Key_Enter:
      case Qt.Key_Space:
        PowerProfiles.profile = visibleProfiles[pwrSel].enumVal;
        break;
      case Qt.Key_H:
      case Qt.Key_Left:
      case Qt.Key_Minus:
        nudgeBrightness(-5);
        break;
      case Qt.Key_L:
      case Qt.Key_Right:
      case Qt.Key_Plus:
      case Qt.Key_Equal:
        nudgeBrightness(5);
        break;
      default:
        event.accepted = false;
    }
  }

  implicitWidth: 438
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
          text: "power"
          color: dropdownRoot.colors[0]
          font.family: "JetBrains Mono"
          font.weight: Font.DemiBold
          font.pixelSize: 13
        }
        Text {
          text: "─ " + dropdownRoot.batteryName + " ─"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
        Text {
          text: dropdownRoot.charging ? "▲ charging" : dropdownRoot.discharging ? "▼ discharging" : "■ on hold"
          color: dropdownRoot.charging ? dropdownRoot.colors[3] : (dropdownRoot.pct <= 20 ? dropdownRoot.colors[1] : dropdownRoot.colors[2])
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      Item { Layout.fillWidth: true }

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

    // ----- battery section -----
    Section {
      width: parent.width
      label: "battery"
      labelColor: dropdownRoot.charging ? dropdownRoot.colors[3] : (dropdownRoot.pct <= 20 ? dropdownRoot.colors[1] : dropdownRoot.colors[2])
      paddingTop: 16
      paddingBottom: 10
      paddingSide: 12
      spacing: 10

      rightContent: Text {
        text: dropdownRoot.charging ? "ac ● connected" : "ac ○ unplugged"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }

      RowLayout {
        width: parent.width
        spacing: 14

        RowLayout {
          spacing: 0

          // The bordered box and the cell Row are siblings, not
          // parent/child -- Row is a positioner and manages its
          // children's x/y itself, so an anchored border rectangle can't
          // be one of those children (anchors and positioner-assigned
          // geometry both fighting over the same properties).
          Item {
            id: cellMeter
            implicitWidth: cellRow.implicitWidth + 8
            implicitHeight: cellRow.implicitHeight + 8

            Rectangle {
              anchors.fill: parent
              border.width: 1
              border.color: dropdownRoot.mutedColor
              radius: 3
              color: "transparent"
            }

            Row {
              id: cellRow
              anchors.centerIn: parent
              spacing: 2
              Repeater {
                model: 20
                Rectangle {
                  required property int index
                  width: 6
                  height: 18
                  radius: 1
                  color: index < dropdownRoot.litCells ? dropdownRoot.levelColor : "#353b45"
                }
              }
            }
          }
          Rectangle {
            Layout.preferredWidth: 3
            Layout.preferredHeight: 10
            radius: 2
            color: dropdownRoot.mutedColor
          }
        }

        ColumnLayout {
          spacing: 0
          Text {
            text: dropdownRoot.pct + "%"
            color: dropdownRoot.fgColor
            font.family: "JetBrains Mono"
            font.pixelSize: 20
            font.weight: Font.DemiBold
          }
          Text {
            text: dropdownRoot.etaText
            color: dropdownRoot.etaColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
        }

        Item { Layout.fillWidth: true }
      }

      RowLayout {
        width: parent.width
        Text {
          text: dropdownRoot.charging ? "charging speed" : "discharge rate"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
        Item { Layout.fillWidth: true }
        Text {
          text: {
            const w = dropdownRoot.signedRate;
            const sign = w > 0 ? "+" : w < 0 ? "−" : "";
            return sign + Math.abs(w).toFixed(1) + " W";
          }
          color: dropdownRoot.signedRate > 0 ? dropdownRoot.colors[3] : dropdownRoot.signedRate < 0 ? dropdownRoot.colors[2] : dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.weight: Font.DemiBold
          font.pixelSize: 13
        }
        Text {
          text: " · avg " + dropdownRoot.rateAvg.toFixed(1) + " W"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      Item {
        width: parent.width
        height: 44

        // RowLayout, not Row -- these bars need per-item bottom alignment
        // at varying heights, which is what Layout.alignment is for; a
        // plain Row would fight the delegate's own anchors for control of
        // y the same way the cell-meter's border rectangle did above.
        RowLayout {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: parent.height
          spacing: 1
          Repeater {
            model: dropdownRoot.rateHistory
            delegate: Rectangle {
              required property real modelData
              Layout.fillWidth: true
              Layout.preferredHeight: Math.max(2, Math.abs(modelData) / dropdownRoot.rateMax * parent.height)
              Layout.alignment: Qt.AlignBottom
              radius: 1
              color: modelData >= 0 ? dropdownRoot.colors[3] : dropdownRoot.colors[2]
              opacity: 0.4 + Math.abs(modelData) / dropdownRoot.rateMax * 0.6
            }
          }
        }
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: 1
          color: dropdownRoot.hoverColor
        }
        Text {
          anchors.top: parent.top
          anchors.right: parent.right
          leftPadding: 6
          text: dropdownRoot.rateMax.toFixed(0) + " W · 60s"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 11

          // Without this the sparkline's own bars show through behind the
          // label instead of sitting cleanly over the top-right corner of
          // the graph.
          Rectangle {
            z: -1
            anchors.fill: parent
            color: "#282c34"
          }
        }
      }

      // Two plain Columns rather than a GridLayout+Repeater with computed
      // Layout.row/Layout.column -- simpler and more predictable than
      // fighting a grid's auto-flow for an explicit "these six rows, two
      // per row" placement (this was a GridLayout originally; not worth
      // it for a fixed 3x2 arrangement that's easier to just write out).
      RowLayout {
        width: parent.width
        spacing: 24

        Column {
          Layout.fillWidth: true
          spacing: 4
          Repeater {
            model: [dropdownRoot.infoRows[0], dropdownRoot.infoRows[2], dropdownRoot.infoRows[4]]
            delegate: RowLayout {
              required property var modelData
              spacing: 4
              Text {
                text: modelData.k
                color: dropdownRoot.mutedColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
              Text {
                text: modelData.v
                color: dropdownRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
                elide: Text.ElideRight
                Layout.maximumWidth: 140
              }
            }
          }
        }

        Column {
          Layout.fillWidth: true
          spacing: 4
          Repeater {
            model: [dropdownRoot.infoRows[1], dropdownRoot.infoRows[3], dropdownRoot.infoRows[5]]
            delegate: RowLayout {
              required property var modelData
              spacing: 4
              Text {
                text: modelData.k
                color: dropdownRoot.mutedColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
              Text {
                text: modelData.v
                color: dropdownRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
                elide: Text.ElideRight
                Layout.maximumWidth: 140
              }
            }
          }
        }
      }
    }

    Item { width: 1; height: 16 }

    // ----- power mode section -----
    Section {
      width: parent.width
      label: "power mode"
      labelColor: dropdownRoot.colors[2]
      paddingTop: 12
      paddingBottom: 6
      paddingSide: 4
      spacing: 2

      rightContent: Text {
        text: "power-profiles-daemon"
        color: dropdownRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }

      Repeater {
        model: dropdownRoot.visibleProfiles
        delegate: Rectangle {
          id: profRow
          required property var modelData
          required property int index

          readonly property bool on: modelData.enumVal === PowerProfiles.profile
          readonly property bool sel: index === dropdownRoot.pwrSel

          width: parent.width
          height: 24
          radius: 2
          color: sel ? "#2f343e" : (rowMouse.containsMouse ? "#2f343e" : "transparent")

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              dropdownRoot.pwrSel = profRow.index;
              PowerProfiles.profile = profRow.modelData.enumVal;
            }
          }

          // Manual x positioning, not RowLayout -- three separate fixed-
          // width-column attempts through RowLayout (marker, then radio,
          // then icon) each failed to actually stop the row shifting
          // depending on which profile was active, and a live diagnostic
          // (temporarily logging each item's resolved x/width) showed why:
          // RowLayout's own constraint solver was producing inconsistent
          // results across the three Repeater-created rows even with
          // Layout.minimumWidth == Layout.maximumWidth pinned on every
          // fixed column -- e.g. "balanced"'s name column landed at
          // x=142 against "performance"'s x=78, a 64px gap neither
          // column's reported width accounted for. That's a RowLayout
          // behavior this file doesn't need to keep fighting: every x
          // below is a plain arithmetic sum of the previous column's own
          // resolved x + width, so there's no constraint solver in the
          // loop to disagree with.
          Text {
            id: markerText
            x: 8
            width: 12
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: profRow.sel ? "▌" : ""
            color: dropdownRoot.colors[0]
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          Text {
            id: radioText
            x: markerText.x + markerText.width + 6
            width: 28
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: profRow.on ? "(•)" : "( )"
            color: profRow.on ? dropdownRoot.colors[2] : dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          Text {
            id: iconText
            x: radioText.x + radioText.width + 6
            width: 18
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Phosphor.icon(profRow.modelData.icon)
            color: profRow.on ? dropdownRoot.colors[profRow.modelData.colorIdx] : dropdownRoot.mutedColor
            font.family: "Phosphor"
            font.pixelSize: 14
          }
          Row {
            id: nameRow
            x: iconText.x + iconText.width + 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text {
              text: profRow.modelData.id
              color: profRow.on ? dropdownRoot.fgColor : "#7f848e"
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              text: profRow.modelData.desc
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: profRow.on ? (dropdownRoot.charging ? "" : dropdownRoot.etaText.replace(" remaining", "")) : ""
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
        }
      }
    }

    Item { width: 1; height: 16 }

    // ----- utilities section -----
    Section {
      width: parent.width
      label: "utilities"
      labelColor: dropdownRoot.mutedColor
      paddingTop: 14
      paddingBottom: 10
      paddingSide: 12
      spacing: 10

      RowLayout {
        width: parent.width
        spacing: 10
        Text {
          text: "brightness"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          Layout.preferredWidth: 78
        }
        // Sized to the block-character text's own width, not
        // Layout.fillWidth -- it used to stretch across the whole row
        // while the visible bar stayed a fixed 20 characters wide, so the
        // draggable area covered a bunch of dead space past the end of
        // what looked like the slider, and clicking there jumped to a
        // position that didn't match where you clicked visually.
        Item {
          id: briTrack
          implicitWidth: briText.implicitWidth
          implicitHeight: briText.implicitHeight
          readonly property int filled: Math.round(dropdownRoot.brightnessPct / 5)
          Text {
            id: briText
            text: "█".repeat(briTrack.filled) + "░".repeat(20 - briTrack.filled)
            color: dropdownRoot.colors[2]
            font.family: "JetBrains Mono"
            font.pixelSize: 13
            elide: Text.ElideNone
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SizeHorCursor
            function setFromX(x) {
              const frac = Math.max(0, Math.min(1, x / width));
              dropdownRoot.setBrightness(Math.round(frac * 20) * 5);
            }
            onPressed: (mouse) => setFromX(mouse.x)
            onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x); }
          }
        }
        Item { Layout.fillWidth: true }
        Text {
          text: dropdownRoot.brightnessPct + "%"
          color: dropdownRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          horizontalAlignment: Text.AlignRight
          Layout.preferredWidth: 32
        }
      }

      // Dashed in the mock; QtQuick has no dashed-border primitive short
      // of a Canvas, and a plain line reads the same at this weight.
      Rectangle {
        width: parent.width
        height: 1
        color: dropdownRoot.hoverColor
      }

      Flow {
        width: parent.width
        spacing: 4
        Repeater {
          model: dropdownRoot.sessionActions
          delegate: Rectangle {
            id: actionBtn
            required property var modelData
            readonly property bool armed: dropdownRoot.armedAction === modelData.id

            implicitWidth: actionRow.implicitWidth + 16
            implicitHeight: 22
            radius: 2
            color: actionMouse.containsMouse ? dropdownRoot.hoverColor : "transparent"
            border.width: 1
            border.color: armed ? dropdownRoot.colors[1] : dropdownRoot.hoverColor

            RowLayout {
              id: actionRow
              anchors.centerIn: parent
              spacing: 6
              Text {
                text: Phosphor.icon(actionBtn.modelData.icon)
                color: actionBtn.armed ? dropdownRoot.colors[1] : dropdownRoot.fgColor
                font.family: "Phosphor"
                font.pixelSize: 13
              }
              Text {
                text: actionBtn.armed ? "confirm?" : actionBtn.modelData.label
                color: actionBtn.armed ? dropdownRoot.colors[1] : dropdownRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 13
              }
            }

            MouseArea {
              id: actionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: dropdownRoot.runSessionAction(actionBtn.modelData)
            }
          }
        }
      }

      Text {
        visible: dropdownRoot.sessionMessage.length > 0
        text: dropdownRoot.sessionMessage
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
      readonly property var hints: [
        { k: "1-3", l: "mode" },
        { k: "j/k ⏎", l: "select" },
        { k: "h/l", l: "brightness" },
        { k: "esc", l: "close" },
      ]
      Repeater {
        model: parent.hints
        RowLayout {
          required property var modelData
          spacing: 4
          Text {
            text: modelData.k
            color: dropdownRoot.colors[2]
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          Text {
            text: modelData.l
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
        }
      }
    }
  }
}

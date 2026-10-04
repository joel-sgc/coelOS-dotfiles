import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../sysPanel/Phosphor.js" as Phosphor

// ===== POWER MENU =====
// Ported from power-menu-example/Power Menu.dc.html -- same mockup-to-QML
// convention as the lock screen (sddm-hyprlock mockup -> lock/). Triggered
// by the hardware power key (home/hyprland.nix's XF86PowerOff bind, via
// coel-power-menu in home/os-commands.nix), not a panel button -- this is
// a separate, standalone Quickshell process (power-menu-shell.qml), not
// part of the main bar's shell.qml/Panel.qml instance, the same
// independent-process convention lock-real-shell.qml already uses for the
// lock screen.
//
// Deliberately distinct from sysPanel/dropdowns/PowerDropdown.qml (the
// battery button's own dropdown, which also has a small session-actions
// row) -- that one's about battery/power-profile detail with session
// actions as an afterthought; this one is a dedicated, keyboard-first
// confirm-before-you-nuke-your-session menu, matching the mockup's own
// much larger, five-tile layout with a per-action arm/countdown/confirm
// step, not just PowerDropdown's single click-again-to-confirm.
//
// Real commands, not the mock's demo ones: logout uses hyprctl since this
// is only ever reached via Hyprland's own power-key bind (see
// configuration.nix's comment: Plasma's physical power key uses systemd's
// own default instead, unrelated to this component).
Item {
  id: root

  property color bgColor: "#21252b"
  property color fgColor: "#abb2bf"
  property color brightColor: "#d7dae0"
  property color mutedColor: "#5c6370"
  property color dimColor: "#7f848e"
  property color borderColor: "#404754"
  property color rowBorderColor: "#2f343e"
  property color rowBg: "#262a31"
  property color selectedBg: "#2c313a"
  property color footerBg: "#1e2127"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"] // blue/red/yellow/green/purple

  signal closeRequested()

  readonly property string username: Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user"
  readonly property string desktopName: (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()

  property string hostName: "coelos"
  property string uptimeText: "—"
  Component.onCompleted: {
    hostnameProc.running = true;
    uptimeProc.running = true;
    root.forceActiveFocus();
  }
  Process {
    id: hostnameProc
    command: ["hostname"]
    stdout: StdioCollector { onStreamFinished: root.hostName = text.trim() }
  }
  // Same /proc/uptime parse as sysPanel/dropdowns/SystemDropdown.qml.
  Process {
    id: uptimeProc
    command: ["sh", "-c", "cat /proc/uptime"]
    stdout: StdioCollector {
      onStreamFinished: {
        const upSec = parseFloat(text.trim().split(" ")[0]);
        if (isNaN(upSec)) return;
        const h = Math.floor(upSec / 3600), m = Math.floor((upSec % 3600) / 60);
        root.uptimeText = h > 0 ? (h + "h " + m + "m") : (m + "m");
      }
    }
  }

  readonly property var device: UPower.displayDevice
  readonly property bool batteryReady: device.ready && device.isLaptopBattery
  readonly property int batteryPct: batteryReady ? Math.round(device.percentage * 100) : 0
  readonly property bool batteryCharging: batteryReady && device.state === UPowerDeviceState.Charging

  readonly property var acts: [
    { k: "lock", label: "lock", icon: "lock-simple", key: "k", safe: true,
      command: ["quickshell", "-p", "/home/joelsgc/.nixos/home/quickshell/lock-real-shell.qml"], cmdText: "quickshell -p lock-real-shell.qml" },
    { k: "suspend", label: "suspend", icon: "moon", key: "s", safe: true,
      command: ["systemctl", "suspend"], cmdText: "systemctl suspend" },
    { k: "logout", label: "log out", icon: "sign-out", key: "l", safe: false,
      command: ["uwsm", "stop"], cmdText: "uwsm stop" },
    { k: "reboot", label: "reboot", icon: "arrow-clockwise", key: "r", safe: false,
      command: ["systemctl", "reboot"], cmdText: "systemctl reboot" },
    { k: "poweroff", label: "shut down", icon: "power", key: "p", safe: false, danger: true,
      command: ["systemctl", "poweroff"], cmdText: "systemctl poweroff" },
  ]
  readonly property int countdown: 5

  property int sel: 0
  property string armed: ""
  property string done: ""
  property int secondsLeft: 0

  Timer { id: armTimer; interval: 1000; repeat: true; onTriggered: root.tickArm() }
  Timer { id: doneTimer; interval: 1600; onTriggered: root.done = "" }

  function actionByKey(k) { return root.acts.find(a => a.k === k) || null; }

  function cancel() {
    armTimer.stop();
    armed = "";
    secondsLeft = 0;
  }

  function run(i) {
    const a = root.acts[i];
    armTimer.stop();
    armed = "";
    secondsLeft = 0;
    done = a.k;
    doneTimer.restart();
    Quickshell.execDetached(a.command);
  }

  function tickArm() {
    const l = root.secondsLeft - 1;
    if (l <= 0) { run(root.sel); return; }
    root.secondsLeft = l;
  }

  function pick(i) {
    const a = root.acts[i];
    if (root.done) return;
    root.sel = i;
    if (a.safe) { run(i); return; }
    if (root.armed === a.k) { run(i); return; }
    armTimer.stop();
    root.armed = a.k;
    root.secondsLeft = root.countdown;
    armTimer.restart();
  }

  readonly property var curAction: acts[sel]
  readonly property var armedAction: armed ? actionByKey(armed) : null
  readonly property var doneAction: done ? actionByKey(done) : null

  readonly property var statusLine: {
    if (doneAction) return { icon: "check", text: doneAction.label + " · running", color: colors[3] };
    if (armedAction) return {
      icon: "warning",
      text: armedAction.label + " in " + secondsLeft + "s · ⏎ now · esc cancel",
      color: armedAction.danger ? colors[1] : colors[2],
    };
    return { icon: "info", text: curAction.label + (curAction.safe ? "" : " · asks to confirm"), color: mutedColor };
  }
  readonly property string statusCmd: "→ " + (armedAction || doneAction || curAction).cmdText

  focus: true
  Keys.onPressed: (event) => {
    event.accepted = true;
    switch (event.key) {
      case Qt.Key_Escape:
        if (root.armed) root.cancel();
        else root.closeRequested();
        break;
      case Qt.Key_Right:
      case Qt.Key_Tab:
        root.cancel();
        root.sel = (root.sel + 1) % root.acts.length;
        break;
      case Qt.Key_Left:
      case Qt.Key_Backtab:
        root.cancel();
        root.sel = (root.sel + root.acts.length - 1) % root.acts.length;
        break;
      case Qt.Key_Return:
      case Qt.Key_Enter:
      case Qt.Key_Space:
        root.pick(root.sel);
        break;
      case Qt.Key_1: case Qt.Key_2: case Qt.Key_3: case Qt.Key_4: case Qt.Key_5: {
        const i = event.key - Qt.Key_1;
        if (i < root.acts.length) { root.cancel(); root.pick(i); }
        break;
      }
      default: {
        const letter = String.fromCharCode(event.key).toLowerCase();
        const j = root.acts.findIndex(a => a.key === letter);
        if (j !== -1) { root.cancel(); root.pick(j); }
        else event.accepted = false;
      }
    }
  }

  // ----- backdrop -----
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(22 / 255, 24 / 255, 29 / 255, 0.62)
  }

  // ----- card -----
  Rectangle {
    id: card
    anchors.centerIn: parent
    width: 620
    radius: 12
    border.width: 1
    border.color: root.borderColor
    color: root.bgColor
    implicitHeight: cardColumn.implicitHeight
    height: implicitHeight

    Column {
      id: cardColumn
      width: parent.width
      spacing: 0

      // ----- header -----
      RowLayout {
        width: parent.width
        height: 58
        Layout.margins: 0

        RowLayout {
          Layout.leftMargin: 18
          spacing: 12
          Rectangle {
            width: 30; height: 30; radius: 15
            color: root.rowBorderColor
            border.width: 1
            border.color: root.borderColor
            Text {
              anchors.centerIn: parent
              text: root.username.charAt(0).toUpperCase()
              color: root.colors[0]
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
          ColumnLayout {
            spacing: 2
            Text {
              text: root.username + "@" + root.hostName
              color: root.brightColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              text: "up " + root.uptimeText + (root.desktopName ? " · " + root.desktopName : "")
              color: root.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 11
            }
          }
        }

        Item { Layout.fillWidth: true }

        RowLayout {
          Layout.rightMargin: 14
          spacing: 16
          RowLayout {
            spacing: 6
            visible: root.batteryReady
            Text {
              text: Phosphor.icon(root.batteryCharging ? "battery-charging" : "battery-high")
              color: root.dimColor
              font.family: "Phosphor"
              font.pixelSize: 15
            }
            Text {
              text: root.batteryPct + "%"
              color: root.dimColor
              font.family: "JetBrains Mono"
              font.pixelSize: 12
            }
          }
          Text {
            text: Phosphor.icon("x")
            color: root.mutedColor
            font.family: "Phosphor"
            font.pixelSize: 14
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: root.closeRequested()
            }
          }
        }
      }
      Rectangle { width: parent.width; height: 1; color: root.rowBorderColor }

      // ----- action grid -----
      // RowLayout wrapped in a plain Item for padding, not Layout.margins
      // directly on the RowLayout -- Layout.* attached properties are only
      // honored when the item sits inside another Layout, and this
      // RowLayout's actual parent is cardColumn, a plain Column
      // positioner, which silently ignores them (confirmed live: the grid
      // was rendering completely flush against the header/status-line
      // dividers above and below it).
      Item {
        width: parent.width
        implicitHeight: grid.implicitHeight + 36
        RowLayout {
          id: grid
          x: 18
          y: 18
          width: parent.width - 36
          spacing: 8

          Repeater {
            model: root.acts
            delegate: Rectangle {
              id: tile
              required property var modelData
              required property int index

              readonly property bool isSel: index === root.sel
              readonly property bool isArmed: root.armed === modelData.k
              readonly property bool isDone: root.done === modelData.k
              readonly property color hot: isArmed
                ? (modelData.danger ? root.colors[1] : root.colors[2])
                : isDone ? root.colors[3]
                : modelData.danger ? root.colors[1] : root.colors[0]

              Layout.fillWidth: true
              Layout.preferredHeight: 118
              radius: 10
              border.width: 1
              border.color: (isSel || isArmed || isDone) ? hot : root.rowBorderColor
              color: (isSel || isArmed) ? root.selectedBg : root.rowBg

              Text {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 7
                anchors.leftMargin: 9
                text: (tile.index + 1) + " " + tile.modelData.key
                color: root.mutedColor
                font.family: "JetBrains Mono"
                font.pixelSize: 10
              }

              ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: Phosphor.icon(tile.modelData.icon)
                  color: (tile.isSel || tile.isArmed || tile.isDone) ? tile.hot : root.dimColor
                  font.family: "Phosphor"
                  font.pixelSize: 28
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: tile.isArmed ? tile.modelData.label + "?" : tile.modelData.label
                  color: (tile.isSel || tile.isArmed) ? root.brightColor : root.dimColor
                  font.family: "JetBrains Mono"
                  font.pixelSize: 12
                }
              }

              Rectangle {
                visible: tile.isArmed
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                anchors.bottomMargin: 8
                height: 2
                radius: 1
                color: root.rowBorderColor
                Rectangle {
                  height: parent.height
                  width: parent.width * (root.secondsLeft / root.countdown)
                  radius: 1
                  color: tile.hot
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { if (!root.armed && !root.done && root.sel !== tile.index) root.sel = tile.index; }
                onClicked: { root.focus = true; root.pick(tile.index); }
              }
            }
          }
        }
      }

      // ----- status line -----
      RowLayout {
        width: parent.width
        Layout.margins: 0
        height: 20
        Layout.leftMargin: 18
        Layout.rightMargin: 18

        RowLayout {
          Layout.leftMargin: 18
          Layout.rightMargin: 18
          Layout.fillWidth: true
          spacing: 10
          Text {
            text: Phosphor.icon(root.statusLine.icon)
            color: root.statusLine.color
            font.family: "Phosphor"
            font.pixelSize: 13
          }
          Text {
            Layout.fillWidth: true
            text: root.statusLine.text
            color: root.statusLine.color
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            elide: Text.ElideRight
          }
          Text {
            text: root.statusCmd
            color: root.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }
        }
      }
      Item { width: 1; height: 14 }

      Rectangle { width: parent.width; height: 1; color: root.rowBorderColor }

      // ----- footer hints -----
      RowLayout {
        width: parent.width
        height: 40
        spacing: 14

        RowLayout {
          Layout.leftMargin: 18
          spacing: 14
          readonly property var hints: [
            { k: "←→", l: "move" },
            { k: "1–5", l: "jump" },
            { k: "⏎", l: "select" },
            { k: "esc", l: root.armed ? "cancel" : "close" },
          ]
          Repeater {
            model: parent.hints
            RowLayout {
              required property var modelData
              spacing: 4
              Text {
                text: modelData.k
                color: root.colors[2]
                font.family: "JetBrains Mono"
                font.pixelSize: 11
              }
              Text {
                text: modelData.l
                color: root.mutedColor
                font.family: "JetBrains Mono"
                font.pixelSize: 11
              }
            }
          }
        }

        Item { Layout.fillWidth: true }

        Image {
          Layout.rightMargin: 18
          source: Qt.resolvedUrl("../assets/coelos-wordmark.png")
          sourceSize.height: 18
          fillMode: Image.PreserveAspectFit
          Layout.preferredWidth: 82
          Layout.preferredHeight: 18
          opacity: 0.85
        }
      }
      Item { width: 1; height: 10 }
    }
  }
}

import QtQuick
import QtQuick.Layouts
import ".."
import "../widgets"

// ===== CAST TAB (view) =====
// The "cast" half of the displays modal (example/Display Modes.dc.html's
// cv block): device list + stream options + route, the wps-pin pairing box,
// the connecting log and the live-session card. Presentation only -- all
// state and actions live in CastBackend.qml (`be`).
ColumnLayout {
  id: tab
  property var be: null
  spacing: 0

  // A "(•) label" option, as in the mockup's share/quality/fps rows.
  component Radio: Rectangle {
    id: radio
    property string label: ""
    property bool on: false
    property bool off: false
    signal picked()
    implicitWidth: rl.implicitWidth + 12
    implicitHeight: rl.implicitHeight
    radius: Globals.eyeCandyOff ? 0 : 2
    color: on || (ra.containsMouse && !off) ? Pal.edge : "transparent"
    opacity: off ? 0.35 : 1
    Row {
      id: rl
      anchors.centerIn: parent
      spacing: 6
      Mono { text: radio.on ? "(•)" : "( )"; color: radio.on ? Pal.blue : Pal.muted }
      Mono { text: radio.label; color: radio.on ? Pal.fg : Pal.dim }
    }
    MouseArea { id: ra; anchors.fill: parent; hoverEnabled: true; cursorShape: radio.off ? Qt.ArrowCursor : Qt.PointingHandCursor; onClicked: if (!radio.off) radio.picked() }
  }

  // ================= list =================
  ColumnLayout {
    visible: be.phase === "list"
    Layout.fillWidth: true
    spacing: 0

    Box {
      Layout.fillWidth: true
      Layout.topMargin: 12
      padTop: 12; padSide: 4; padBottom: 4
      legend: "nearby"
      rightLegend: ""
      rightData: [
        Mono { text: be.scanning ? "scanning " + be.spinner : be.found.length + " found"; color: be.scanning ? Pal.yellow : Pal.muted },
        TextButton {
          hPad: 4
          onClicked: be.scan()
          Mono { text: "[↻]"; color: parent.parent.hovered ? Pal.fg : Pal.muted }
        }
      ]

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
          model: be.found
          delegate: Rectangle {
            id: devRow
            required property string modelData
            required property int index
            readonly property var d: be.dev(modelData)
            readonly property bool sel: index === be.sel
            readonly property bool isLive: be.live !== null && be.live.id === modelData
            Layout.fillWidth: true
            implicitHeight: devLay.implicitHeight + 12
            radius: Globals.eyeCandyOff ? 0 : 4
            color: sel ? Pal.raised : (devMouse.containsMouse ? Pal.raised : "transparent")
            opacity: d.unsupported ? 0.5 : 1

            MouseArea {
              id: devMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: be.sel = devRow.index
              onDoubleClicked: { be.sel = devRow.index; be.connectSelected(); }
            }
            RowLayout {
              id: devLay
              anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
              spacing: 8
              Mono { Layout.preferredWidth: 8; text: devRow.sel ? "▌" : ""; color: Pal.blue }
              PhIcon { Layout.preferredWidth: 18; name: devRow.d.icon; font.pixelSize: 16; color: devRow.d.color; horizontalAlignment: Text.AlignHCenter }
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Mono { Layout.fillWidth: true; text: devRow.d.name; color: devRow.sel ? Pal.fg : Pal.dim; elide: Text.ElideRight }
                Mono { Layout.fillWidth: true; text: devRow.d.model + " · " + devRow.d.proto; font.pixelSize: 11; color: Pal.muted; elide: Text.ElideRight }
              }
              Mono {
                text: devRow.isLive ? "● casting" : devRow.d.unsupported ? "unsupported" : devRow.d.busy ? "busy" : devRow.d.pin ? "pin" : ""
                font.pixelSize: 11
                color: devRow.isLive ? Pal.green : (devRow.d.unsupported || devRow.d.busy) ? Pal.muted : Pal.yellow
              }
              Mono {
                text: "▂▄▆█".slice(0, devRow.d.signal) + "·".repeat(4 - devRow.d.signal)
                color: devRow.d.signal >= 3 ? Pal.green : Pal.yellow
                font.letterSpacing: 1
              }
            }
          }
        }

        Mono {
          visible: be.scanning
          Layout.leftMargin: 6
          Layout.bottomMargin: 4
          text: "searching wi-fi direct + mdns " + be.spinner
          color: Pal.muted
        }
        Mono {
          visible: !be.scanning && be.found.length === 0
          Layout.fillWidth: true
          Layout.margins: 6
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: "no displays found · turn on screen mirroring on the tv, then <font color=\"" + Pal.yellow + "\">r</font> rescan"
          color: Pal.muted
        }
      }
    }

    Mono {
      visible: be.errorText !== "" || be.scanNote !== ""
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.leftMargin: 4
      wrapMode: Text.Wrap
      text: be.errorText !== "" ? "✗ " + be.errorText : "! " + be.scanNote
      color: be.errorText !== "" ? Pal.red : Pal.yellow
      font.pixelSize: 11
    }

    Box {
      Layout.fillWidth: true
      Layout.topMargin: 16
      padTop: 12; padSide: 6; padBottom: 6
      legend: "stream"

      GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 4

        Mono { Layout.leftMargin: 4; text: "share"; color: Pal.muted }
        Flow {
          Layout.fillWidth: true
          spacing: 6
          Radio { label: "mirror laptop"; on: be.source === "mirror"; onPicked: be.source = "mirror" }
          Radio { label: "extend · new display"; on: be.source === "extend"; onPicked: be.source = "extend" }
        }

        Mono { Layout.leftMargin: 4; text: "quality"; color: Pal.muted }
        Flow {
          Layout.fillWidth: true
          spacing: 6
          Repeater {
            model: [720, 1080, 1440, 2160]
            delegate: Radio {
              required property int modelData
              label: be.resLabel(modelData)
              on: be.shownRes === modelData
              off: !!be.selDev && modelData > be.selDev.max
              onPicked: be.res = modelData
            }
          }
        }

        Mono { Layout.leftMargin: 4; text: "fps"; color: Pal.muted }
        Flow {
          Layout.fillWidth: true
          spacing: 6
          Radio { label: "30"; on: be.fps === 30; onPicked: be.fps = 30 }
          Radio { label: "60"; on: be.fps === 60; onPicked: be.fps = 60 }
        }

        Mono { Layout.leftMargin: 4; text: "audio"; color: Pal.muted }
        TextButton {
          hoverColor: Pal.edge
          onClicked: be.audio = !be.audio
          Mono { text: be.audio ? "[x]" : "[ ]"; color: be.audio ? Pal.green : Pal.muted }
          Mono { text: be.audio ? "play on the tv" : "keep on the laptop"; color: Pal.fg }
        }
      }
    }

    Box {
      Layout.fillWidth: true
      Layout.topMargin: 16
      padTop: 12; padSide: 10; padBottom: 6
      legend: "route"
      rightLegend: be.selDev ? be.selDev.proto : ""
      rightColor: be.selDev && be.selDev.unsupported ? Pal.red : Pal.muted

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        Repeater {
          model: {
            const d = be.selDev;
            if (!d) return [];
            if (d.unsupported) return ["airplay sending is not available on linux"];
            const rl = be.resLabel(be.shownRes);
            return [
              be.source === "extend" ? "hyprctl output create headless CAST-1" : "capture eDP-1 · xdg-desktop-portal · pipewire",
              d.proto === "miracast" ? "wi-fi direct p2p · wpa_supplicant" : "mdns _googlecast._tcp · same network as the tv",
              d.proto === "miracast" ? "h.264 " + rl + " @" + be.fps + " → rtsp sink" : "vp8 " + rl + " @" + be.fps + " → cast receiver",
              be.audio ? "audio · pipewire monitor → stream" : "audio · stays on the laptop"
            ];
          }
          delegate: RowLayout {
            required property string modelData
            Layout.fillWidth: true
            spacing: 6
            Mono { Layout.preferredWidth: 12; Layout.alignment: Qt.AlignTop; text: "→"; font.pixelSize: 11; color: Pal.muted }
            Mono { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; text: modelData; font.pixelSize: 11; color: Pal.dim }
          }
        }
      }
    }
  }

  // ================= pin =================
  Box {
    visible: be.phase === "pin"
    Layout.fillWidth: true
    Layout.topMargin: 12
    padTop: 16; padSide: 12; padBottom: 12
    legend: "pair"
    legendColor: Pal.blue
    rightLegend: "miracast · wps pin"
    borderColor: be.pinErr ? Pal.red : Pal.faint

    Mono {
      Layout.fillWidth: true
      Layout.bottomMargin: 10
      wrapMode: Text.Wrap
      textFormat: Text.StyledText
      text: "enter the 8-digit pin shown on <font color=\"" + Pal.fg + "\">" + (be.selDev ? be.selDev.name : "") + "</font>"
      color: Pal.dim
    }
    RowLayout {
      spacing: 8
      Mono { text: "❯"; color: Pal.blue }
      Rectangle {
        Layout.preferredWidth: 180
        Layout.preferredHeight: pinInput.implicitHeight + 10
        color: pinInput.activeFocus ? Pal.raised : Pal.deep
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: pinInput.activeFocus ? Pal.blue : Pal.faint }
        TextInput {
          id: pinInput
          anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
          verticalAlignment: TextInput.AlignVCenter
          color: Pal.fg
          font.family: Pal.mono
          font.pixelSize: 18
          font.letterSpacing: 4
          inputMethodHints: Qt.ImhDigitsOnly
          maximumLength: 9
          text: be.pin
          onTextEdited: {
            const v = text.replace(/\D/g, "").slice(0, 8);
            be.pin = v.length > 4 ? v.slice(0, 4) + " " + v.slice(4) : v;
            be.pinErr = "";
            text = be.pin;
          }
          Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { be.pair(); e.accepted = true; }
            else if (e.key === Qt.Key_Escape) { be.phase = "list"; e.accepted = true; }
          }
          Mono { visible: pinInput.text.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "•••• ••••"; font.pixelSize: 18; font.letterSpacing: 4; color: Pal.muted }
        }
      }
    }
    Mono { visible: be.pinErr !== ""; Layout.topMargin: 8; text: be.pinErr; color: Pal.red }
  }
  // Focus the field when pairing starts; the modal takes it back afterwards.
  property alias pinField: pinInput
  Connections {
    target: tab.be
    function onPhaseChanged() { if (tab.be.phase === "pin") Qt.callLater(() => pinInput.forceActiveFocus()); }
  }

  // ================= connecting =================
  Box {
    visible: be.phase === "connecting"
    Layout.fillWidth: true
    Layout.topMargin: 12
    padTop: 14; padSide: 10; padBottom: 10
    legend: "connecting · " + (be.dev(be.target) ? be.dev(be.target).name : "")
    legendColor: Pal.yellow
    rightLegend: Math.min(be.step, be.steps.length) + "/" + be.steps.length

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2
      Repeater {
        model: be.steps
        delegate: RowLayout {
          required property string modelData
          required property int index
          readonly property bool done: index < be.step
          readonly property bool cur: index === be.step
          Layout.fillWidth: true
          spacing: 8
          Mono { Layout.preferredWidth: 14; text: done ? "✓" : cur ? be.spinner : "·"; color: done ? Pal.green : cur ? Pal.yellow : Pal.faint }
          Mono { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData; color: done ? Pal.dim : cur ? Pal.fg : Pal.muted }
        }
      }
    }
  }

  // ================= live =================
  Box {
    visible: be.phase === "live" && be.live !== null
    Layout.fillWidth: true
    Layout.topMargin: 12
    padTop: 16; padSide: 12; padBottom: 10
    legend: "● casting"
    legendColor: Pal.green
    rightLegend: be.live ? be.fmtTime(be.now - be.live.start) : ""
    rightColor: Pal.dim
    borderColor: Pal.green

    RowLayout {
      Layout.fillWidth: true
      spacing: 12
      Rectangle {
        Layout.preferredWidth: 40; Layout.preferredHeight: 40
        radius: Globals.eyeCandyOff ? 0 : 8
        color: Pal.edge
        PhIcon { anchors.centerIn: parent; name: be.liveDev ? be.liveDev.icon : "screencast"; font.pixelSize: 22; color: be.liveDev ? be.liveDev.color : Pal.fg }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Mono { Layout.fillWidth: true; text: be.liveDev ? be.liveDev.name : ""; elide: Text.ElideRight }
        Mono { Layout.fillWidth: true; text: be.liveDev ? be.liveDev.model + " · " + be.liveDev.proto : ""; color: Pal.muted; elide: Text.ElideRight }
      }
      TextButton {
        onClicked: be.changeDevice()
        Mono { text: "[change]"; color: parent.parent.hovered ? Pal.fg : Pal.dim }
      }
    }

    DashedLine { Layout.fillWidth: true; Layout.topMargin: 10 }
    GridLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      columns: 2
      columnSpacing: 12
      rowSpacing: 2
      Repeater {
        model: {
          const L = be.live, d = be.liveDev;
          if (!L || !d) return [];
          const br = { 720: 4, 1080: 8, 1440: 12, 2160: 20 };
          const mbps = (br[L.res] * L.fps / 30 * 0.75 + Math.sin(be.now / 1500) * 0.6).toFixed(1);
          const lat = (d.proto === "miracast" ? 72 : 180) + Math.round(Math.sin(be.now / 2300) * 8);
          return [["share", L.source === "extend" ? "extended display CAST-1" : "mirroring eDP-1"],
                  ["quality", be.resLabel(L.res) + " @" + L.fps],
                  ["stream", mbps + " Mbps · " + lat + " ms"],
                  ["audio", L.audio ? "on the tv" : "on the laptop"]].flat();
        }
        delegate: Mono {
          required property string modelData
          required property int index
          Layout.column: index % 2
          color: index % 2 === 0 ? Pal.muted : Pal.fg
          text: modelData
        }
      }
    }
  }
}

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Pipewire
import "./Phosphor.js" as Phosphor

// ===== AUDIO DROPDOWN =====
// Phase 5b: real data/actions, replacing phase 5a's hardcoded layout.
//
// Devices view (sinks/sources, volume, mute, set-default, mic level) is
// fully real via Quickshell.Services.Pipewire -- the same PwNode/
// PwObjectTracker API Volume.qml's bar icon already uses, plus
// PwNodePeakMonitor for a genuine input level instead of the old
// cosmetic jitter.
//
// Cards view's profile + ports are real too, but through a different
// path: Quickshell's Pipewire API has *no* card/device/profile/port
// surface at all (checked the actual qmltypes -- Pipewire/PwNodeIface/
// PwNodeAudioIface/PwNodePeakMonitor/PwObjectTracker is the whole
// surface). Reading those needs `pw-dump`, writing them needs
// `wpctl set-profile`/`set-route` -- the same "shell out for what the
// native API doesn't cover" pattern nmcli/bluetoothctl play elsewhere in
// this repo.
//
// TODO(cards): sample rate, quantum, and "suspend when idle" are
// deliberately left out rather than faked. Rate/quantum are real
// PipeWire settings, but they live on the graph (`pw-metadata`), not per
// card the way the design mock models them; forcing them onto a
// per-card control would misrepresent what they actually are. No tool
// exposes "suspend when idle" as a readable/settable value at all --
// it's a WirePlumber config default, not runtime state. Confirmed with
// the user (2026-09-25) this scope is intentional, not a shortcut.
//
// Device rows mix several fixed-width columns (marker/radio/volume-bar/
// pct/mute), so they use manual x/anchors positioning, not RowLayout --
// same reasoning as PowerDropdown.qml's profile rows and NetworkDropdown's
// network list.
Item {
  id: dropdownRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  property bool popupOpen: false

  signal closeRequested()

  property string view: "devices" // "devices" | "cards"
  property string devFocus: "out" // "out" | "in" -- which devices list j/k/h/l/m/enter act on
  property int outSel: 0
  property int inSel: 0
  property int cardSel: 0

  // ----- real sink/source lists -----
  // ALSA's auto-generated HDA descriptions run long ("Radeon High
  // Definition Audio Controller Pro 7") -- "High Definition Audio
  // Controller"/"HD Audio Controller" is generic chipset-class
  // boilerplate common across Realtek/Intel/AMD HDA cards, not a real
  // distinguishing word, so it's trimmed for the row display. The
  // untrimmed node.name is still shown in the row's own sub-line.
  function trimBoilerplate(name) {
    return name.replace(/\s*(High Definition|HD) Audio Controller\s*/i, " ").replace(/\s+/g, " ").trim();
  }
  function displayName(n) {
    let name = n.name;
    if (n.description && n.description.length > 0) name = n.description;
    else if (n.nickname && n.nickname.length > 0) name = n.nickname;
    return trimBoilerplate(name);
  }
  // AudioSink/AudioSource both include the base "Audio" bit (confirmed
  // against Quickshell's own source: Audio=0b1, Source=0b1000,
  // Sink=0b10000, AudioSink=Audio|Sink=17, AudioSource=Audio|Source=9).
  // A plain truthy `type & PwNodeType.AudioSource` test is wrong for a
  // *combined* flag value like that -- it only proves the shared Audio
  // bit is set (true for every audio node, sinks included), not that
  // the Source bit specifically is. This was pulling every sink into
  // the source list and vice versa. `(type & Flag) === Flag` requires
  // every bit of the target flag to be present, which is the actual
  // "has this flag" test.
  readonly property var allSinks: {
    const out = [];
    for (const n of Pipewire.nodes.values) {
      if (!n.isStream && (n.type & PwNodeType.AudioSink) === PwNodeType.AudioSink) out.push(n);
    }
    return out;
  }
  readonly property var allSources: {
    const out = [];
    for (const n of Pipewire.nodes.values) {
      if (!n.isStream && (n.type & PwNodeType.AudioSource) === PwNodeType.AudioSource) out.push(n);
    }
    return out;
  }

  // Nodes are inert until tracked -- same requirement Volume.qml's bar
  // icon already documented for the default sink (untracked, volume/
  // muted never update after the first read).
  PwObjectTracker {
    objects: dropdownRoot.allSinks.concat(dropdownRoot.allSources)
  }

  function setVol(dir, node, vol) {
    if (!node || !node.audio) return;
    node.audio.volume = Math.max(0, Math.min(100, vol)) / 100;
  }
  function toggleMute(dir, node) {
    if (!node || !node.audio) return;
    node.audio.muted = !node.audio.muted;
  }
  function makeDefault(dir, node) {
    if (!node) return;
    if (dir === "out") Pipewire.preferredDefaultAudioSink = node;
    else Pipewire.preferredDefaultAudioSource = node;
  }

  readonly property var outRows: mkRows(allSinks, "out")
  readonly property var inRows: mkRows(allSources, "in")
  function mkRows(list, dir) {
    const def = dir === "out" ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
    const sel = dir === "out" ? outSel : inSel;
    const isFocus = devFocus === dir;
    return list.map((n, i) => ({
      pwNode: n, index: i, av: true,
      name: displayName(n),
      mute: n.audio ? n.audio.muted : false,
      vol: n.audio ? Math.round(n.audio.volume * 100) : 0,
      isDefault: n === def,
      isSel: isFocus && i === sel,
      filled: n.audio ? Math.round(n.audio.volume * 20) : 0,
      sub: n.name + " · #" + n.id,
    }));
  }
  onOutRowsChanged: outSel = Math.max(0, Math.min(outSel, outRows.length - 1))
  onInRowsChanged: inSel = Math.max(0, Math.min(inSel, inRows.length - 1))

  // ----- real mic level meter -----
  PwNodePeakMonitor {
    id: peakMonitor
    node: Pipewire.defaultAudioSource
    enabled: dropdownRoot.popupOpen && dropdownRoot.view === "devices" && Pipewire.defaultAudioSource !== null
  }

  // ----- cards: profile + ports real via pw-dump (read) + wpctl
  // (write) -- see header TODO for what's deliberately left out. -----
  property var cards: []
  property string pipewireVersion: ""
  Process {
    id: cardsProc
    command: ["pw-dump"]
    stdout: StdioCollector {
      onStreamFinished: {
        let data;
        try { data = JSON.parse(text); } catch (e) { return; }
        const out = [];
        for (const obj of data) {
          if (obj.type === "PipeWire:Interface:Core") {
            dropdownRoot.pipewireVersion = (obj.info && obj.info.version) || "";
            continue;
          }
          if (obj.type !== "PipeWire:Interface:Device") continue;
          const info = obj.info || {};
          const props = info.props || {};
          if (props["media.class"] !== "Audio/Device") continue;
          const params = info.params || {};
          const profiles = (params.EnumProfile || []).filter(p => p.available !== "no");
          const activeProfile = (params.Profile || [])[0];
          const routes = params.EnumRoute || [];
          const activeRoutes = params.Route || [];
          const api = props["device.api"] || "";
          out.push({
            id: obj.id,
            name: dropdownRoot.trimBoilerplate(props["device.description"] || props["device.nick"] || props["device.name"] || ("device #" + obj.id)),
            api,
            bus: props["device.bus"] || "",
            driver: api === "alsa" ? (props["api.alsa.card.name"] || "alsa") : api,
            icon: api === "bluez5" ? "headphones" : api === "usb" ? "usb" : "cpu",
            profile: activeProfile ? activeProfile.description : "",
            profileIndex: activeProfile ? activeProfile.index : -1,
            profiles: profiles.map(p => ({ index: p.index, name: p.description })),
            outPorts: routes.filter(r => r.direction === "Output").map(r => ({
              index: r.index, name: r.description,
              avail: r.available !== "no",
              active: activeRoutes.some(a => a.index === r.index),
            })),
            inPorts: routes.filter(r => r.direction === "Input").map(r => ({
              index: r.index, name: r.description,
              avail: r.available !== "no",
              active: activeRoutes.some(a => a.index === r.index),
            })),
          });
        }
        dropdownRoot.cards = out;
      }
    }
  }
  Timer {
    interval: 4000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: cardsProc.running = true
  }
  onCardsChanged: cardSel = Math.max(0, Math.min(cardSel, cards.length - 1))

  Process { id: profileProc; onExited: cardsProc.running = true }
  function setCardProfile(cardId, profileIndex) {
    profileProc.command = ["wpctl", "set-profile", String(cardId), String(profileIndex)];
    profileProc.running = true;
  }
  Process { id: routeProc; onExited: cardsProc.running = true }
  function setCardRoute(cardId, routeIndex) {
    routeProc.command = ["wpctl", "set-route", String(cardId), String(routeIndex)];
    routeProc.running = true;
  }

  readonly property var selectedCard: cards.length > 0 ? cards[Math.min(cardSel, cards.length - 1)] : null
  function cycleProfile() {
    const c = selectedCard;
    if (!c || c.profiles.length === 0) return;
    const idx = c.profiles.findIndex(p => p.index === c.profileIndex);
    const next = c.profiles[(idx + 1 + c.profiles.length) % c.profiles.length];
    setCardProfile(c.id, next.index);
  }

  focus: true
  Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Escape) { closeRequested(); event.accepted = true; return; }
    if (event.key === Qt.Key_1) { view = "devices"; event.accepted = true; return; }
    if (event.key === Qt.Key_2) { view = "cards"; event.accepted = true; return; }
    event.accepted = true;

    if (view === "cards") {
      switch (event.key) {
        case Qt.Key_J:
        case Qt.Key_Down:
          cardSel = Math.min(cards.length - 1, cardSel + 1);
          break;
        case Qt.Key_K:
        case Qt.Key_Up:
          cardSel = Math.max(0, cardSel - 1);
          break;
        case Qt.Key_P:
          cycleProfile();
          break;
        default:
          event.accepted = false;
      }
      return;
    }

    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      devFocus = devFocus === "out" ? "in" : "out";
      return;
    }
    const rows = devFocus === "out" ? outRows : inRows;
    const sel = devFocus === "out" ? outSel : inSel;
    const row = rows[sel];
    switch (event.key) {
      case Qt.Key_J:
      case Qt.Key_Down:
        if (devFocus === "out") outSel = Math.min(outRows.length - 1, outSel + 1);
        else inSel = Math.min(inRows.length - 1, inSel + 1);
        break;
      case Qt.Key_K:
      case Qt.Key_Up:
        if (devFocus === "out") outSel = Math.max(0, outSel - 1);
        else inSel = Math.max(0, inSel - 1);
        break;
      case Qt.Key_H:
      case Qt.Key_Left:
        if (row) setVol(devFocus, row.pwNode, row.vol - 5);
        break;
      case Qt.Key_L:
      case Qt.Key_Right:
        if (row) setVol(devFocus, row.pwNode, row.vol + 5);
        break;
      case Qt.Key_M:
        if (row) toggleMute(devFocus, row.pwNode);
        break;
      case Qt.Key_Return:
      case Qt.Key_Enter:
      case Qt.Key_D:
        if (row) makeDefault(devFocus, row.pwNode);
        break;
      default:
        event.accepted = false;
    }
  }

  // 32px less than Panel.qml's Popup contentWidth (600) -- that's
  // Popup.qml's own 16px-per-side content padding, not a separate
  // number to pick freely. Every other dropdown keeps this same 32px
  // gap (470/438, 480/448, 500/468); setting this equal to contentWidth
  // instead of contentWidth-32 is exactly what caused the right-edge
  // overflow -- confirmed via live diagnostic: dropdownRoot was
  // rendering at the full 600px inside a container only 568px wide.
  implicitWidth: 568
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
        Text { text: "audio"; color: dropdownRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
        Text {
          text: "─ pipewire " + (dropdownRoot.pipewireVersion.length > 0 ? dropdownRoot.pipewireVersion : "…") + " ─"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
        Text {
          text: Pipewire.ready ? "● running" : "○ connecting…"
          color: Pipewire.ready ? dropdownRoot.colors[3] : dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        implicitWidth: devTabLabel.implicitWidth + 16
        implicitHeight: 20
        radius: 2
        color: dropdownRoot.view === "devices" ? dropdownRoot.hoverColor : "transparent"
        Text {
          id: devTabLabel
          anchors.centerIn: parent
          text: "1 devices"
          color: dropdownRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.view = "devices" }
      }
      Rectangle {
        implicitWidth: cardTabLabel.implicitWidth + 16
        implicitHeight: 20
        radius: 2
        color: dropdownRoot.view === "cards" ? dropdownRoot.hoverColor : "transparent"
        Text {
          id: cardTabLabel
          anchors.centerIn: parent
          text: "2 cards"
          color: dropdownRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.view = "cards" }
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

    // ===== DEVICES VIEW =====
    Column {
      visible: dropdownRoot.view === "devices"
      width: parent.width
      spacing: 16

      Item { width: 1; height: 8 }

      Section {
        width: parent.width
        label: "output"
        labelColor: dropdownRoot.devFocus === "out" ? dropdownRoot.colors[0] : dropdownRoot.mutedColor
        borderColor: dropdownRoot.devFocus === "out" ? "#4b5263" : dropdownRoot.hoverColor
        paddingTop: 10
        paddingBottom: 6
        paddingSide: 4
        spacing: 1

        rightContent: Text {
          text: "default ─ " + (Pipewire.defaultAudioSink ? dropdownRoot.displayName(Pipewire.defaultAudioSink) : "—")
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }

        Repeater {
          model: dropdownRoot.outRows
          delegate: DeviceRow {
            width: parent.width
            row: modelData
            dir: "out"
            fgColor: dropdownRoot.fgColor
            mutedColor: dropdownRoot.mutedColor
            colors: dropdownRoot.colors
            onSelect: { dropdownRoot.devFocus = "out"; dropdownRoot.outSel = modelData.index; }
            onMakeDefault: { dropdownRoot.devFocus = "out"; dropdownRoot.outSel = modelData.index; dropdownRoot.makeDefault("out", modelData.pwNode); }
            onDragVolume: (frac) => dropdownRoot.setVol("out", modelData.pwNode, Math.round(frac * 20) * 5)
            onToggleMute: dropdownRoot.toggleMute("out", modelData.pwNode)
          }
        }
        Text {
          visible: dropdownRoot.outRows.length === 0
          x: 8
          text: "no output devices found"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      Section {
        width: parent.width
        label: "input"
        labelColor: dropdownRoot.devFocus === "in" ? dropdownRoot.colors[0] : dropdownRoot.mutedColor
        borderColor: dropdownRoot.devFocus === "in" ? "#4b5263" : dropdownRoot.hoverColor
        paddingTop: 10
        paddingBottom: 6
        paddingSide: 4
        spacing: 1

        rightContent: Text {
          text: "default ─ " + (Pipewire.defaultAudioSource ? dropdownRoot.displayName(Pipewire.defaultAudioSource) : "—")
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }

        Repeater {
          model: dropdownRoot.inRows
          delegate: DeviceRow {
            width: parent.width
            row: modelData
            dir: "in"
            fgColor: dropdownRoot.fgColor
            mutedColor: dropdownRoot.mutedColor
            colors: dropdownRoot.colors
            onSelect: { dropdownRoot.devFocus = "in"; dropdownRoot.inSel = modelData.index; }
            onMakeDefault: { dropdownRoot.devFocus = "in"; dropdownRoot.inSel = modelData.index; dropdownRoot.makeDefault("in", modelData.pwNode); }
            onDragVolume: (frac) => dropdownRoot.setVol("in", modelData.pwNode, Math.round(frac * 20) * 5)
            onToggleMute: dropdownRoot.toggleMute("in", modelData.pwNode)
          }
        }
        Text {
          visible: dropdownRoot.inRows.length === 0
          x: 8
          text: "no input devices found"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }

        Item {
          width: parent.width
          implicitHeight: levelRow.implicitHeight + 8

          Rectangle { y: 0; width: parent.width; height: 1; color: dropdownRoot.hoverColor }

          RowLayout {
            id: levelRow
            y: 7
            width: parent.width
            spacing: 10
            Text { text: "level"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            Row {
              spacing: 2
              readonly property bool live: Pipewire.defaultAudioSource !== null && !(Pipewire.defaultAudioSource.audio && Pipewire.defaultAudioSource.audio.muted)
              readonly property real lv: live ? peakMonitor.peak : 0
              readonly property int lit: Math.round(Math.min(1, lv) * 28)
              Repeater {
                model: 28
                delegate: Rectangle {
                  required property int index
                  width: 7
                  height: 10
                  radius: 1
                  color: index < parent.parent.lit ? (index < 18 ? dropdownRoot.colors[3] : index < 24 ? dropdownRoot.colors[2] : dropdownRoot.colors[1]) : "#353b45"
                }
              }
            }
            Text {
              readonly property bool hasSource: Pipewire.defaultAudioSource !== null
              readonly property bool muted: hasSource && Pipewire.defaultAudioSource.audio && Pipewire.defaultAudioSource.audio.muted
              readonly property bool live: hasSource && !muted
              readonly property real lv: live ? peakMonitor.peak : 0
              text: !hasSource ? "no source" : live ? Math.max(-60, 20 * Math.log10(Math.max(lv, 0.001))).toFixed(0) + " dB" : muted ? "muted" : "no signal"
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
        }
      }
    }

    // ===== CARDS VIEW =====
    Column {
      visible: dropdownRoot.view === "cards"
      width: parent.width
      spacing: 16

      Item { width: 1; height: 8 }

      Section {
        width: parent.width
        label: "cards (" + dropdownRoot.cards.length + ")"
        labelColor: dropdownRoot.colors[0]
        paddingTop: 10
        paddingBottom: 6
        paddingSide: 4
        spacing: 2

        Repeater {
          model: dropdownRoot.cards
          delegate: Rectangle {
            id: cardRow
            required property var modelData
            required property int index
            readonly property bool sel: index === dropdownRoot.cardSel

            width: parent.width
            height: 22
            radius: 2
            color: sel ? "#2f343e" : (cardMouse.containsMouse ? "#2f343e" : "transparent")

            MouseArea {
              id: cardMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: dropdownRoot.cardSel = cardRow.index
            }

            Text {
              x: 8
              width: 10
              anchors.verticalCenter: parent.verticalCenter
              text: cardRow.sel ? "▌" : ""
              color: dropdownRoot.colors[0]
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              id: cardIcon
              x: 24
              anchors.verticalCenter: parent.verticalCenter
              text: Phosphor.icon(cardRow.modelData.icon)
              color: dropdownRoot.colors[0]
              font.family: "Phosphor"
              font.pixelSize: 14
            }
            Text {
              id: cardApi
              anchors.right: cardProfile.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: cardRow.modelData.api
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              id: cardProfile
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              width: 190
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              text: cardRow.modelData.profile
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
            Text {
              x: 48
              anchors.right: cardApi.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: cardRow.modelData.name
              color: dropdownRoot.fgColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
        }
        Text {
          visible: dropdownRoot.cards.length === 0
          x: 8
          text: "no audio devices found"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      Rectangle {
        visible: dropdownRoot.selectedCard !== null
        width: parent.width
        height: settingsCol.implicitHeight + 28
        radius: 2
        color: "transparent"
        border.width: 1
        border.color: dropdownRoot.hoverColor

        Text {
          x: 8
          y: -9
          leftPadding: 6
          rightPadding: 6
          text: "settings ─ " + (dropdownRoot.selectedCard ? dropdownRoot.selectedCard.name : "")
          color: dropdownRoot.colors[2]
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          Rectangle { z: -1; anchors.fill: parent; color: "#282c34" }
        }

        ColumnLayout {
          id: settingsCol
          x: 14
          y: 14
          width: parent.width - 28
          spacing: 6

          FormField {
            label: "driver"
            mode: "text"
            fieldEnabled: false
            value: dropdownRoot.selectedCard ? (dropdownRoot.selectedCard.driver + " · " + dropdownRoot.selectedCard.bus + " · " + dropdownRoot.selectedCard.api) : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
          }
          FormField {
            label: "profile"
            mode: "cycle"
            value: dropdownRoot.selectedCard ? dropdownRoot.selectedCard.profile : ""
            fgColor: dropdownRoot.fgColor
            labelColor: dropdownRoot.mutedColor
            hoverColor: dropdownRoot.hoverColor
            accentColor: dropdownRoot.colors[2]
            onCycled: dropdownRoot.cycleProfile()
          }
          Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "sample rate/quantum/suspend-when-idle aren't shown -- those are graph-wide PipeWire settings, not really per card, and suspend-when-idle isn't exposed as readable/settable state by any available tool"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }

          Item {
            implicitWidth: 1
            implicitHeight: 4
          }
          Text { text: "output ports"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Repeater {
              model: dropdownRoot.selectedCard ? dropdownRoot.selectedCard.outPorts : []
              delegate: PortRow {
                required property var modelData
                Layout.fillWidth: true
                port: modelData
                fgColor: dropdownRoot.fgColor
                mutedColor: dropdownRoot.mutedColor
                accentColor: dropdownRoot.colors[2]
                onPick: dropdownRoot.setCardRoute(dropdownRoot.selectedCard.id, modelData.index)
              }
            }
            Text {
              visible: dropdownRoot.selectedCard && dropdownRoot.selectedCard.outPorts.length === 0
              text: "— none in this profile"
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }

          Text { text: "input ports"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Repeater {
              model: dropdownRoot.selectedCard ? dropdownRoot.selectedCard.inPorts : []
              delegate: PortRow {
                required property var modelData
                Layout.fillWidth: true
                port: modelData
                fgColor: dropdownRoot.fgColor
                mutedColor: dropdownRoot.mutedColor
                accentColor: dropdownRoot.colors[2]
                onPick: dropdownRoot.setCardRoute(dropdownRoot.selectedCard.id, modelData.index)
              }
            }
            Text {
              visible: dropdownRoot.selectedCard && dropdownRoot.selectedCard.inPorts.length === 0
              text: "— none in this profile"
              color: dropdownRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }
          }
        }
      }
    }

    Item { width: 1; height: 12 }

    // ----- hints -----
    Flow {
      width: parent.width
      spacing: 14
      readonly property var hints: dropdownRoot.view === "devices"
        ? [{ k: "tab", l: dropdownRoot.devFocus === "out" ? "input" : "output" }, { k: "j/k", l: "move" }, { k: "h/l", l: "volume" }, { k: "m", l: "mute" }, { k: "⏎", l: "set default" }, { k: "2", l: "cards" }, { k: "esc", l: "close" }]
        : [{ k: "j/k", l: "card" }, { k: "p", l: "profile" }, { k: "1", l: "devices" }, { k: "esc", l: "close" }]
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
}

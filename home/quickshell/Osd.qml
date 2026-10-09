import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

import "./sysPanel/Phosphor.js" as Phosphor

// ===== OSD =====
// Replaces swayosd: a volume/brightness/media on-screen-display, ported
// from example/OSD.dc.html. Real data throughout, no hardcoded-UI-first
// pass needed here (simple enough, like the power menu's own "real
// commands went in directly during the port" precedent) -- every data
// source below is already a proven pattern elsewhere in this project:
//   - volume: Pipewire.defaultAudioSink, same API sysPanel/buttons/
//     Volume.qml already uses (PwObjectTracker required -- a PwNode's
//     audio properties stay inert until tracked).
//   - brightness: a FileView against /sys/class/backlight/amdgpu_bl1,
//     the exact same device + FileView quirks (blockWrites/atomicWrites
//     both false, or writes silently never take effect against a sysfs
//     pseudo-file) sysPanel/dropdowns/PowerDropdown.qml's own slider
//     already established.
//   - media: Quickshell.Services.Mpris -- genuinely new, the first real
//     MPRIS integration anywhere in this repo (the lock screen's own
//     MediaWidget.qml is explicitly fake/demo-driven, by its own
//     comment).
// Mic-mute is deliberately not covered here (stays launcher-only, per
// explicit scope decision) -- no mic state, no keybind added for it.
Scope {
  id: osdScope

  // ----- real volume -----
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
  PwObjectTracker { objects: osdScope.sink ? [osdScope.sink] : [] }

  // ----- real brightness -----
  readonly property string backlightDevice: "/sys/class/backlight/amdgpu_bl1"
  FileView {
    id: brightnessFile
    path: osdScope.backlightDevice + "/brightness"
    watchChanges: true
    onFileChanged: reload()
    blockWrites: false
    atomicWrites: false
  }
  FileView {
    id: maxBrightnessFile
    path: osdScope.backlightDevice + "/max_brightness"
  }
  readonly property int maxBrightness: parseInt(maxBrightnessFile.text()) || 0
  readonly property int brightnessPct: maxBrightness > 0
    ? Math.round((parseInt(brightnessFile.text()) || 0) / maxBrightness * 100)
    : 0
  function setBrightnessPct(pct) {
    if (maxBrightness <= 0) return;
    const clamped = Math.max(1, Math.min(100, pct));
    brightnessFile.setText(String(Math.round(clamped / 100 * maxBrightness)));
  }

  // ----- real media -----
  // Prefers whichever player is actually playing, then one that at least
  // has real track metadata, falling back to just the first one Mpris
  // knows about -- there's no single "active" player concept in the MPRIS
  // spec itself. The metadata-first fallback is real, not theoretical:
  // confirmed live with two simultaneous kdeconnect.mpris_* players (one
  // per phone-side media session), one of them a genuinely empty
  // placeholder with no trackTitle/artist/art at all -- plain `list[0]`
  // picked that empty one every time instead of the real one.
  readonly property var player: {
    const list = Mpris.players.values;
    for (const p of list) if (p.isPlaying) return p;
    for (const p of list) if (p.trackTitle && p.trackTitle.length > 0) return p;
    return list.length > 0 ? list[0] : null;
  }
  function fmtTime(sec) {
    const s = Math.max(0, Math.floor(sec || 0));
    return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
  }

  // ----- show/hide -----
  property string kind: "vol" // "vol" | "bri" | "media"
  property bool shown: false
  Timer { id: hideTimer; interval: 1500; onTriggered: osdScope.shown = false }
  function flash(k) {
    osdScope.kind = k;
    osdScope.shown = true;
    hideTimer.restart();
  }

  // ----- real actions, called from the IpcHandler below -----
  readonly property real volStep: 0.05
  function volumeUp() {
    if (sink && sink.audio) {
      sink.audio.muted = false;
      sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + volStep));
    }
    flash("vol");
  }
  function volumeDown() {
    if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume - volStep));
    flash("vol");
  }
  function volumeMuteToggle() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
    flash("vol");
  }
  readonly property int briStep: 5
  function brightnessUp() { setBrightnessPct(brightnessPct + briStep); flash("bri"); }
  function brightnessDown() { setBrightnessPct(brightnessPct - briStep); flash("bri"); }
  function mediaPlayPause() { if (player) player.togglePlaying(); flash("media"); }
  function mediaNext() { if (player && player.canGoNext) player.next(); flash("media"); }
  function mediaPrevious() { if (player && player.canGoPrevious) player.previous(); flash("media"); }

  // `quickshell ipc -p ~/.nixos/home/quickshell call osd <fn>` -- what
  // home/hyprland.nix's XF86* media/volume/brightness keys call now,
  // replacing swayosd-client (volume/brightness) and a playerctl+
  // notify-send pipeline (media, which never had a real OSD before this).
  IpcHandler {
    target: "osd"
    function volumeUp(): void { osdScope.volumeUp(); }
    function volumeDown(): void { osdScope.volumeDown(); }
    function volumeMuteToggle(): void { osdScope.volumeMuteToggle(); }
    function brightnessUp(): void { osdScope.brightnessUp(); }
    function brightnessDown(): void { osdScope.brightnessDown(); }
    function mediaPlayPause(): void { osdScope.mediaPlayPause(); }
    function mediaNext(): void { osdScope.mediaNext(); }
    function mediaPrevious(): void { osdScope.mediaPrevious(); }
  }

  // One per screen, shown on all of them simultaneously (not just the
  // focused one) -- matches real swayosd's own behavior, and unlike
  // Launcher/Notifications' click-or-keybind-triggered toggle, there's no
  // single "screen you meant" to resolve for a plain media-key press.
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: osdWin
        required property var modelData
        screen: modelData

        // No left/right anchor -- same "omit the cross anchor to get
        // automatic horizontal centering" convention Popup.qml's own
        // centerHorizontally relies on.
        anchors { bottom: true }
        margins.bottom: 72

        implicitWidth: pill.implicitWidth
        implicitHeight: pill.implicitHeight

        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        visible: osdScope.shown

        Rectangle {
          id: pill
          implicitWidth: osdScope.kind === "media" ? 400 : 340
          // Directly off whichever row is actually active, +28 (14px top
          // and bottom) -- no intermediate wrapper Item in between anymore.
          // That wrapper's own `centerIn` still wasn't actually centering
          // the real rendered content (confirmed live, twice: a visible
          // top/bottom gap mismatch persisted even after switching to
          // centerIn), which turned out to mean the problem was never the
          // centering *mechanism* -- it was that both rows, pill, and the
          // wrapper were all separately guessing at the same height
          // instead of one one thing owning it. Each row now anchors its
          // own verticalCenter directly to `pill` (safe -- pill is a plain
          // Rectangle, not a Row/Column positioner, so this doesn't hit
          // the anchoring-a-positioner's-own-child issue documented
          // elsewhere in this project), and pill's own height is driven
          // by that exact same row, not a separate guess.
          implicitHeight: (osdScope.kind === "media" ? mediaRow.implicitHeight : levelRow.implicitHeight) + 28
          radius: Globals.eyeCandyOff ? 0 : 16
          color: "#282c34"
          border.width: 1
          border.color: "#404754"
          opacity: osdScope.shown ? 1 : 0
          scale: osdScope.shown ? 1 : 0.98
          Behavior on opacity { NumberAnimation { duration: 180 } }
          Behavior on scale { NumberAnimation { duration: 180 } }

          // ----- level view (volume/brightness) -----
          RowLayout {
              id: levelRow
              visible: osdScope.kind !== "media"
              anchors.verticalCenter: parent.verticalCenter
              x: 14
              width: parent.width - 28
              spacing: 12

              Text {
                text: osdScope.kind === "bri"
                  ? (osdScope.brightnessPct < 35 ? Phosphor.icon("sun-dim") : Phosphor.icon("sun"))
                  : (osdScope.muted || osdScope.vol === 0 ? Phosphor.icon("speaker-x") : osdScope.vol < 0.5 ? Phosphor.icon("speaker-low") : Phosphor.icon("speaker-high"))
                font.family: "Phosphor"
                font.pixelSize: 20
                color: osdScope.kind === "bri" ? "#e5c07b" : (osdScope.muted ? "#5c6370" : "#61afef")
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                  Layout.fillWidth: true
                  spacing: 8
                  Text { text: osdScope.kind === "bri" ? "brightness" : (osdScope.muted ? "muted" : "volume"); color: "#7f848e"; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                  Item { Layout.fillWidth: true }
                  Text {
                    visible: osdScope.kind === "vol" && osdScope.sink !== null && osdScope.sink.description
                    text: osdScope.sink && osdScope.sink.description ? osdScope.sink.description : ""
                    color: "#5c6370"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    Layout.maximumWidth: 150
                  }
                }

                Rectangle {
                  Layout.fillWidth: true
                  height: 6
                  radius: Globals.eyeCandyOff ? 0 : 1
                  color: "#353b45"
                  Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: Globals.eyeCandyOff ? 0 : 1
                    width: parent.width * (osdScope.kind === "bri" ? osdScope.brightnessPct / 100 : (osdScope.muted ? 0 : osdScope.vol))
                    color: osdScope.kind === "bri" ? "#e5c07b" : "#61afef"
                  }
                }
              }

              Text {
                text: osdScope.kind === "bri" ? (osdScope.brightnessPct + "%") : (osdScope.muted ? "—" : Math.round(osdScope.vol * 100) + "%")
                color: osdScope.kind === "bri" ? "#abb2bf" : (osdScope.muted ? "#5c6370" : "#abb2bf")
                font.family: "JetBrains Mono"
                font.pixelSize: 13
                Layout.alignment: Qt.AlignRight
              }
            }

          // ----- media view -----
          RowLayout {
              id: mediaRow
              visible: osdScope.kind === "media"
              anchors.verticalCenter: parent.verticalCenter
              x: 14
              width: parent.width - 28
              spacing: 12

              Rectangle {
                width: 44; height: 44; radius: Globals.eyeCandyOff ? 0 : 8
                color: "#21252b"
                clip: true
                Image {
                  id: artImg
                  anchors.fill: parent
                  source: osdScope.player && osdScope.player.trackArtUrl ? osdScope.player.trackArtUrl : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  visible: status === Image.Ready
                }
                Text {
                  visible: artImg.status !== Image.Ready
                  anchors.centerIn: parent
                  text: Phosphor.icon("music-notes")
                  font.family: "Phosphor"
                  font.pixelSize: 20
                  color: "#5c6370"
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                  Layout.fillWidth: true
                  spacing: 6
                  Text {
                    text: osdScope.player && osdScope.player.isPlaying ? "▶" : "❚❚"
                    color: osdScope.player && osdScope.player.isPlaying ? "#89ca78" : "#e5c07b"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                  }
                  Text {
                    Layout.fillWidth: true
                    text: osdScope.player ? osdScope.player.trackTitle : "no player"
                    color: "#d7dae0"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 13
                    elide: Text.ElideRight
                  }
                }
                Text {
                  Layout.fillWidth: true
                  text: osdScope.player ? (osdScope.player.trackArtist + " · " + osdScope.player.identity) : ""
                  color: "#7f848e"
                  font.family: "JetBrains Mono"
                  font.pixelSize: 12
                  elide: Text.ElideRight
                }
                RowLayout {
                  Layout.fillWidth: true
                  spacing: 8
                  Text { text: osdScope.player ? osdScope.fmtTime(osdScope.player.position) : "0:00"; color: "#5c6370"; font.family: "JetBrains Mono"; font.pixelSize: 11 }
                  Rectangle {
                    Layout.fillWidth: true
                    height: 3
                    radius: Globals.eyeCandyOff ? 0 : 1
                    color: "#353b45"
                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      radius: Globals.eyeCandyOff ? 0 : 1
                      width: osdScope.player && osdScope.player.length > 0 ? parent.width * Math.max(0, Math.min(1, osdScope.player.position / osdScope.player.length)) : 0
                      color: "#61afef"
                    }
                  }
                  Text { text: osdScope.player ? osdScope.fmtTime(osdScope.player.length) : "0:00"; color: "#5c6370"; font.family: "JetBrains Mono"; font.pixelSize: 11 }
                }
              }

              // Matches the mock's own transport cluster: prev/next are
              // plain icon buttons, play/pause gets a visible accent
              // border so the primary action actually stands out instead
              // of all three looking identical.
              RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Rectangle {
                  width: 28; height: 28; radius: Globals.eyeCandyOff ? 0 : 6
                  color: prevMouse.containsMouse ? "#2f343e" : "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: Phosphor.icon("skip-back")
                    font.family: "Phosphor"
                    font.pixelSize: 15
                    color: "#7f848e"
                  }
                  MouseArea { id: prevMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: osdScope.mediaPrevious() }
                }
                Rectangle {
                  width: 28; height: 28; radius: Globals.eyeCandyOff ? 0 : 6
                  color: toggleMouse.containsMouse ? "#2f343e" : "transparent"
                  border.width: 1
                  border.color: "#61afef"
                  Text {
                    anchors.centerIn: parent
                    text: osdScope.player && osdScope.player.isPlaying ? Phosphor.icon("pause") : Phosphor.icon("play")
                    font.family: "Phosphor"
                    font.pixelSize: 15
                    color: "#61afef"
                  }
                  MouseArea { id: toggleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: osdScope.mediaPlayPause() }
                }
                Rectangle {
                  width: 28; height: 28; radius: Globals.eyeCandyOff ? 0 : 6
                  color: nextMouse.containsMouse ? "#2f343e" : "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: Phosphor.icon("skip-forward")
                    font.family: "Phosphor"
                    font.pixelSize: 15
                    color: "#7f848e"
                  }
                  MouseArea { id: nextMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: osdScope.mediaNext() }
                }
              }
            }
          }
        }
      }
    }
  }

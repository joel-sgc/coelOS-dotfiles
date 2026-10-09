import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

import "./sysPanel/Phosphor.js" as Phosphor
import "./notifications"

// ===== NOTIFICATIONS =====
// Owns the real NotificationsBackend (the actual org.freedesktop.Notifications
// D-Bus server -- this is what replaces mako), the notification toast stack
// (one PanelWindow per screen, same Variants-over-Quickshell.screens shape
// as Border.qml), and the global `quickshell ipc call notifications toggle`
// handler (same shape as Launcher.qml's own IpcHandler).
Scope {
  id: notifScope

  // Instantiated exactly once, here -- never inside Panel.qml's per-screen
  // Variants, which would try to register the D-Bus service once per
  // monitor. Exposed as `backend` for shell.qml to thread down into Panel
  // (Bell.qml's badge, NotificationsDropdown.qml) the same way
  // bgColor/fgColor/colors already flow.
  property alias backend: backendItem
  NotificationsBackend { id: backendItem }

  // Live countdown driving each non-critical toast's auto-dismiss progress
  // bar -- ticks only while there's at least one toast up, not constantly.
  property var nowTick: new Date()
  Timer {
    interval: 100
    running: notifScope.backend.toasts.length > 0
    repeat: true
    onTriggered: {
      notifScope.nowTick = new Date();
      for (const t of notifScope.backend.toasts) {
        if (t.until !== null && notifScope.nowTick.getTime() >= t.until) {
          notifScope.backend.fadeToast(t.id);
        }
      }
    }
  }
  function toastPct(t) {
    if (t.until === null) return 1;
    return Math.max(0, Math.min(1, (t.until - notifScope.nowTick.getTime()) / (notifScope.backend.toastSeconds * 1000)));
  }
  function toastTime(t) {
    const secs = Math.floor((notifScope.nowTick.getTime() - t.createdAt) / 1000);
    if (secs < 60) return "now";
    return Math.floor(secs / 60) + "m ago";
  }

  function resolveFocusedScreen() {
    const mon = Hyprland.focusedMonitor;
    let screen = null;
    if (mon) {
      for (const s of Quickshell.screens) {
        if (s.name === mon.name) { screen = s; break; }
      }
    }
    if (!screen && Quickshell.screens.length > 0) screen = Quickshell.screens[0];
    return screen;
  }

  signal toggleRequested(var screen)

  // `quickshell ipc -p ~/.nixos/home/quickshell call notifications toggle`
  // -- super+ctrl+shift+n (home/hyprland.nix), opening/closing the dropdown
  // on whichever screen currently has focus, same resolveFocusedScreen()
  // pattern Launcher.qml's own IpcHandler already uses.
  IpcHandler {
    target: "notifications"
    function toggle(): void {
      notifScope.toggleRequested(notifScope.resolveFocusedScreen());
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: toastWin
        required property var modelData
        screen: modelData

        anchors {
          top: true
          right: true
        }
        // Matches where real tiled windows actually sit, not a guessed
        // gap -- confirmed empirically via `hyprctl -j clients` (a real
        // window's own `at`: [22, 46] on this monitor) rather than derived
        // purely from config, since the real figure also includes
        // general:border_size (2) on top of Panel.qml's own 36px
        // exclusive zone (`hyprctl -j monitors`' own "reserved": [0,36,0,0])
        // plus home/hyprland.nix's gaps_out ("8, 20, 20, 20" ->
        // top/right/bottom/left). top: 36 + 8 + 2 = 46; right: 20 + 2 = 22.
        // Hardcoded, like every other dropdown's own rightMargin in this
        // project -- revisit if gaps_out, border_size, or barHeight ever
        // change.
        margins {
          top: 44
          right: 20
        }

        implicitWidth: 340
        implicitHeight: toastColumn.implicitHeight

        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Column {
          id: toastColumn
          width: parent.width
          spacing: 8

          Repeater {
            model: notifScope.backend.toasts
            delegate: Rectangle {
              id: toastCard
              required property var modelData
              width: toastColumn.width
              implicitHeight: toastRow.implicitHeight + 22
              // Matches home/hyprland.nix's decoration.rounding (8), not a
              // separately-chosen value -- toasts sit right next to real
              // windows (same corner radius as this project's "eye candy"
              // toggle bundle also references, TogglesBackend.qml), so
              // their own corners should match exactly.
              radius: Globals.eyeCandyOff ? 0 : 8
              color: "#282c34"
              border.width: 2
              border.color: toastCard.modelData.isCrit ? "#ef596f" : "#404754"
              // The countdown bar below is a plain sharp-cornered
              // Rectangle anchored to the bottom-left -- without this it
              // visibly extended past the card's own rounded corner
              // instead of being contained by it.
              clip: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: notifScope.toggleRequested(toastWin.modelData)
              }

              Row {
                id: toastRow
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 10

                // Real image thumbnail when the notification has one,
                // instead of a generic per-app glyph -- same reasoning as
                // the dropdown's own row/detail icon slots (the glyph
                // doesn't identify anything useful for e.g. Satty, where
                // the image itself is the real content). A fixed-size Item
                // so it still behaves as one ordinary Row child regardless
                // of which of its own two children ends up visible.
                Item {
                  width: 22; height: 22
                  anchors.verticalCenter: parent.verticalCenter

                  Image {
                    id: toastImage
                    anchors.fill: parent
                    source: (toastCard.modelData.image && toastCard.modelData.image.length > 0) ? toastCard.modelData.image : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                  }
                  Text {
                    visible: toastImage.status !== Image.Ready
                    anchors.centerIn: parent
                    text: Phosphor.icon(toastCard.modelData.icon)
                    font.family: "Phosphor"
                    font.pixelSize: 18
                    color: toastCard.modelData.isCrit ? "#ef596f" : "#61afef"
                  }
                }

                Column {
                  width: parent.width - 18 - 10 - 16
                  spacing: 2

                  Row {
                    spacing: 6
                    Text { text: toastCard.modelData.app; color: "#5c6370"; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                    Text { text: "·"; color: "#5c6370"; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                    Text { text: notifScope.toastTime(toastCard.modelData); color: "#5c6370"; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                  }
                  Text { width: parent.width; text: toastCard.modelData.summary; color: "#d7dae0"; font.family: "JetBrains Mono"; font.pixelSize: 13; elide: Text.ElideRight }
                  Text { width: parent.width; text: toastCard.modelData.body; color: "#7f848e"; font.family: "JetBrains Mono"; font.pixelSize: 13; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                }
              }

              Text {
                id: dismissText
                text: "[×]"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                color: "#5c6370"
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  cursorShape: Qt.PointingHandCursor
                  onClicked: notifScope.backend.dismissToast(toastCard.modelData.id)
                }
              }
              Text {
                visible: toastCard.modelData.isCrit
                text: "critical"
                anchors.verticalCenter: dismissText.verticalCenter
                anchors.right: dismissText.left
                anchors.rightMargin: 8
                color: "#ef596f"
                font.family: "JetBrains Mono"
                font.pixelSize: 12
              }

              // Inset just enough to clear the rounded corner's actual
              // curve at this bar's height, not the card's full radius --
              // 8px (the full radius) was far more clearance than a 2px
              // bar sitting 2px above the bottom edge geometrically needs
              // (circle of radius 8, 2px up from the tangent point: the
              // curve has already pulled in by under 3px at that height),
              // so the bar looked noticeably short of the real width
              // instead of just missing the corner. `clip` on toastCard
              // doesn't help here regardless -- QtQuick's `clip` always
              // clips to the item's plain axis-aligned bounding box, never
              // to a `radius`-shaped region (confirmed live: adding it
              // changed nothing).
              Rectangle {
                readonly property int cornerInset: 4
                visible: !toastCard.modelData.isCrit
                x: cornerInset
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                height: 2
                radius: Globals.eyeCandyOff ? 0 : 1
                width: (parent.width - cornerInset * 2) * notifScope.toastPct(toastCard.modelData)
                color: toastCard.modelData.isCrit ? "#ef596f" : "#61afef"
              }
            }
          }
        }
      }
    }
  }
}

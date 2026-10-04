import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

import "./launcher"

// ===== LAUNCHER =====
// Full-screen "Spotlight" overlay -- the rofi replacement for coel-main-menu.
// Structurally different from Popup.qml's dropdowns: those anchor under a
// specific bar button on one edge of the bar; this is a centered modal over
// the *whole screen* with its own dimmed backdrop, so it gets its own
// PanelWindow chrome here rather than reusing Popup.qml.
//
// One PanelWindow per screen (same Variants-over-Quickshell.screens pattern
// as Border.qml/Panel.qml), but only the screen it was actually invoked on
// shows it -- `activeScreen` (set by whichever Logo button opened it, via
// shell.qml) decides which of the per-screen instances that is, since a
// screen-spanning window still exists on every monitor even while hidden.
Scope {
  id: launcherScope

  property bool open: false
  property var activeScreen: null
  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property color bgColor: "#282c34"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  // The one process-wide NotificationsBackend instance (threaded in from
  // shell.qml, same as Panel.qml's own `notifications` prop) -- only
  // consumed by LauncherPanel's TogglesBackend, to repoint its "Do not
  // disturb" toggle at the real backend instead of `makoctl`.
  property var notifications: null
  // Set by shell.qml right before opening via openCategoryRequested --
  // consumed once by LauncherPanel's onPanelOpenChanged, not reset here
  // (shell.qml clears it back to "" on a plain toggle so a later
  // super+space doesn't keep forcing the same category).
  property string requestedCategory: ""
  // Same one-shot-set-before-open idea as requestedCategory, but a live
  // search restriction rather than a starting tab -- forwarded straight
  // through to LauncherPanel.searchScope, not consumed-and-cleared.
  property string requestedScope: ""

  signal closeRequested()
  // Bubbled up from LauncherPanel's "panels" category items -- shell.qml
  // forwards this into Panel.qml's own openPopup state and closes this.
  signal openPanelRequested(var screen, string name)
  // Fired by the IpcHandler below (a Hyprland keybind, not a Logo click),
  // which has no button/screen context of its own to work from -- shell.qml
  // reacts to this the same way it reacts to Panel's launcherToggleRequested.
  signal toggleRequested(var screen)
  // Same idea as toggleRequested, but also names a category to force the
  // launcher onto -- used by super+V (openClipboard below) to jump
  // straight to the clipboard tab rather than whatever was last open.
  signal openCategoryRequested(var screen, string catId)
  // Like openCategoryRequested, but restricts what fuzzyList() searches at
  // all rather than just picking a starting tab -- used by super+.
  // (openEmoji below) for an emoji-only launcher.
  signal openScopeRequested(var screen, string scope)

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

  // `quickshell ipc call launcher toggle` -- what home/hyprland.nix's
  // super+space / super+shift+space binds actually run now, replacing the
  // direct `rofi -show drun` / `coel-main-menu` exec they used to.
  IpcHandler {
    target: "launcher"
    function toggle(): void {
      launcherScope.toggleRequested(launcherScope.resolveFocusedScreen());
    }
    // `quickshell ipc call launcher openClipboard` -- super+V, replacing
    // the old `cliphist list | rofi -dmenu | cliphist decode | wl-copy`
    // pipeline (home/hyprland.nix).
    function openClipboard(): void {
      launcherScope.openCategoryRequested(launcherScope.resolveFocusedScreen(), "clipboard");
    }
    // `quickshell ipc call launcher openEmoji` -- super+., replacing the
    // old rofi-emoji-based `coel-emoji-picker` (home/hyprland.nix).
    function openEmoji(): void {
      launcherScope.openScopeRequested(launcherScope.resolveFocusedScreen(), "emoji");
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: winRoot
        required property var modelData
        screen: modelData

        readonly property bool shown: launcherScope.open && launcherScope.activeScreen === modelData

        visible: shown
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        anchors {
          top: true
          left: true
          right: true
          bottom: true
        }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Dimmed backdrop -- click anywhere on it (outside the card) closes,
        // matching the mock's own scrim behavior.
        Rectangle {
          anchors.fill: parent
          color: "#18181b"
          opacity: winRoot.shown ? 0.55 : 0
          Behavior on opacity { NumberAnimation { duration: 120 } }

          MouseArea {
            anchors.fill: parent
            onClicked: launcherScope.closeRequested()
          }
        }

        LauncherPanel {
          id: panelContent
          anchors.horizontalCenter: parent.horizontalCenter
          // Was `y: parent.height * 0.16`, matching the mock's own literal
          // `top:16vh` -- true vertical centering instead, per the user
          // reporting the fixed-offset version sat noticeably higher than
          // centered on the real screen. Trades away the mock's original
          // reasoning (a fixed top offset means the card's top edge never
          // jumps as content height changes with search results) for
          // matching what "centered" actually means here -- worth
          // revisiting if the vertical jump while typing turns out to be
          // more distracting than the off-center position was.
          anchors.verticalCenter: parent.verticalCenter
          fgColor: launcherScope.fgColor
          mutedColor: launcherScope.mutedColor
          hoverColor: launcherScope.hoverColor
          bgColor: launcherScope.bgColor
          colors: launcherScope.colors
          notifications: launcherScope.notifications
          panelOpen: winRoot.shown
          requestedCategory: launcherScope.requestedCategory
          searchScope: launcherScope.requestedScope
          onCloseRequested: launcherScope.closeRequested()
          onOpenPanelRequested: (name) => launcherScope.openPanelRequested(winRoot.modelData, name)
        }
      }
    }
  }
}

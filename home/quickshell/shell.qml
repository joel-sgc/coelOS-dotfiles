import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

import "./sysPanel"

ShellRoot {
  id: root
  property var bgColor: "#282c34"
  property var fgColor: "#abb2bf"
  // Dimmed/secondary text -- tray icons at rest, separators between button
  // groups. Same value the design mock uses for both roles.
  property var mutedColor: "#5c6370"
  // Hover background for every bar chip (workspace, logo, clock, tray,
  // bt/net/audio/sys/pwr) -- also doubles as the tray group's separator
  // line color in the mock, which is the same #404754.
  property var hoverColor: "#404754"
  property var colors: [
    "#61afef",  // Blue
    "#ef596f",  // Red
    "#e5c07b",  // Yellow
    "#89ca78",  // Green
    "#d55fde"   // Purple
  ]
  // Single source of truth for the bar's height -- Border needs it too
  // (its overlay leaves a barHeight-tall gap at the top), and Popup.qml's
  // instances anchor their top margin to it as well.
  property int barHeight: 36

  // One shared Launcher instance across every screen (not per-screen state
  // like Panel's own openPopup) -- launcherScreen is which screen it should
  // actually render on, set by whichever screen's Logo button opened it
  // (or, for the Hyprland-keybind path, Launcher.qml's own IpcHandler).
  property bool launcherOpen: false
  property var launcherScreen: null
  // Forces the launcher onto a specific category on open (currently just
  // "clipboard", via super+V) -- cleared on a plain toggle so a later
  // super+space doesn't keep re-forcing whatever category super+V last set.
  property string launcherRequestedCategory: ""
  // Restricts what the launcher searches at all while open (currently just
  // "emoji", via super+.) -- same clear-on-plain-toggle rule, and mutually
  // exclusive with launcherRequestedCategory (opening one clears the other,
  // so e.g. super+. after a super+V doesn't leave a stale clipboard jump
  // active underneath an emoji-only search).
  property string launcherRequestedScope: ""
  function toggleLauncher(screen) {
    launcherRequestedCategory = "";
    launcherRequestedScope = "";
    if (launcherOpen && launcherScreen === screen) launcherOpen = false;
    else { launcherScreen = screen; launcherOpen = true; }
  }
  function openLauncherCategory(screen, catId) {
    launcherRequestedScope = "";
    if (launcherOpen && launcherScreen === screen && launcherRequestedCategory === catId) {
      launcherOpen = false;
    } else {
      launcherScreen = screen;
      launcherRequestedCategory = catId;
      launcherOpen = true;
    }
  }
  function openLauncherScope(screen, scope) {
    launcherRequestedCategory = "";
    if (launcherOpen && launcherScreen === screen && launcherRequestedScope === scope) {
      launcherOpen = false;
    } else {
      launcherScreen = screen;
      launcherRequestedScope = scope;
      launcherOpen = true;
    }
  }

  // Waybar-like panel
  Panel {
    id: panel
    colors: root.colors
    bgColor: root.bgColor
    fgColor: root.fgColor
    mutedColor: root.mutedColor
    hoverColor: root.hoverColor
    barHeight: root.barHeight
    onLauncherToggleRequested: (screen) => root.toggleLauncher(screen)
  }

  // Wraparound border -- borderColor is intentionally bound to the opaque
  // bgColor here rather than left at Border.qml's own translucent default;
  // confirmed with the user, not an oversight.
  Border {
    borderColor: root.bgColor
    barHeight: root.barHeight
  }

  // Spotlight-style launcher (rofi replacement) -- see Launcher.qml
  Launcher {
    open: root.launcherOpen
    activeScreen: root.launcherScreen
    bgColor: root.bgColor
    fgColor: root.fgColor
    mutedColor: root.mutedColor
    hoverColor: root.hoverColor
    colors: root.colors
    requestedCategory: root.launcherRequestedCategory
    requestedScope: root.launcherRequestedScope
    onCloseRequested: root.launcherOpen = false
    onToggleRequested: (screen) => root.toggleLauncher(screen)
    onOpenCategoryRequested: (screen, catId) => root.openLauncherCategory(screen, catId)
    onOpenScopeRequested: (screen, scope) => root.openLauncherScope(screen, scope)
    // "panels" category items (Network/Bluetooth/.../Calendar) -- forward
    // straight into Panel's own openPopup state, same as clicking that
    // bar button directly would.
    onOpenPanelRequested: (screen, name) => panel.openPanelRequested(screen, name)
  }
}
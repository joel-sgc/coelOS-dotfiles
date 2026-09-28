import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

import "./buttons"
import "./dropdowns"

// One PanelWindow per screen, same Variants-over-Quickshell.screens pattern
// as Border.qml (which already did this) -- Panel used to be a single bare
// PanelWindow with no `screen` set, so it only ever rendered on whichever
// screen Quickshell picked as the default, unlike Border which already
// spans every monitor. shell.qml's own `Panel { colors: ...; bgColor: ...;
// fgColor: ... }` usage doesn't need to change for this -- those three
// properties just moved from the PanelWindow itself up to this file's new
// top-level Scope, which is what shell.qml is actually binding to either
// way.
//
// `id: root` staying on the PanelWindow (not the outer Scope) is
// deliberate: every child file (Workspaces.qml, Buttons.qml -> Button.qml
// -> Cpu/Battery/Bluetooth/Network/Volume.qml) reaches panel state via an
// unqualified `root.fgColor`/`root.colors`/`root.workspaceCount` -- that
// resolves through QML's context-parent chain to whichever object actually
// has `id: root`, wherever it's declared, so keeping it directly on the
// PanelWindow (same relative position as before) is what keeps all of
// that working unchanged. The `Component { }` wrapper Variants requires
// gives this PanelWindow its own separate id-scope, so reusing "root"
// here doesn't clash with anything outside it.
Scope {
  id: panelScope

  property var bgColor: "#282c34"
  property var fgColor: "#abb2bf"
  property var mutedColor: "#5c6370"
  property var hoverColor: "#404754"
  property var colors: [
    "#61afef",  // Blue
    "#ef596f",  // Red
    "#e5c07b",  // Yellow
    "#89ca78",  // Green
    "#d55fde"   // Purple
  ]
  property int barHeight: 36

  // Bubbled up from whichever screen's Logo button was clicked, since
  // shell.qml owns the actual Launcher open/closed state (one launcher
  // instance shared across every screen, not per-screen state like
  // openPopup below) and needs to know which screen to show it on.
  signal launcherToggleRequested(var screen)
  // The reverse direction -- shell.qml calls this (via LauncherPanel's
  // "panels" category) to open a specific dropdown on a specific screen,
  // same as clicking that screen's own bar button would. A signal rather
  // than a settable property because openPopup lives per-screen inside
  // the Variants delegate below, not on panelScope itself.
  signal openPanelRequested(var screen, string name)

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: root
        required property var modelData
        screen: modelData

        property var bgColor: panelScope.bgColor
        property var fgColor: panelScope.fgColor
        property var mutedColor: panelScope.mutedColor
        property var hoverColor: panelScope.hoverColor
        property var colors: panelScope.colors
        property int barHeight: panelScope.barHeight

        // Which dropdown (if any) is open, by name -- "" means none.
        // A single string rather than one bool per button so opening one
        // popup always closes any other (matches the design mock's own
        // togglePwr/toggleBt/etc, each of which zeroes out every other
        // *Open flag) without an O(n^2) tangle of "close everyone else"
        // calls as more dropdowns get wired up across phases 3-6.
        property string openPopup: ""
        // Which SystemTrayItem (Quickshell.Services.SystemTray) the tray's
        // shared dropdown below is currently showing -- Tray.qml sets this
        // right before setting openPopup = "tray", since a single Popup
        // instance is reused for every tray icon rather than giving each
        // one its own (there can be any number of them, unlike the fixed
        // bluetooth/network/audio/system buttons).
        property var trayMenuItem: null

        Connections {
          target: panelScope
          function onOpenPanelRequested(screen, name) {
            if (screen === root.screen) root.openPopup = name;
          }
        }

        property int workspaceCount: {
          let maxWs = 5;
          for (const ws of Hyprland.workspaces.values) {
            if (ws.id > maxWs) maxWs = ws.id;
          }
          return maxWs;
        }

        anchors {
          top: true
          left: true
          right: true
        }

        implicitHeight: root.barHeight
        color: root.bgColor

        // Above Border.qml's own screen-edge overlay (which sits one
        // layer down, at Top) so the bar's popups/dropdowns render over
        // the border frame instead of being drawn behind it.
        WlrLayershell.layer: WlrLayer.Overlay

        RowLayout {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 14

          Logo {
            Layout.leftMargin: 12
            onClicked: panelScope.launcherToggleRequested(root.screen)
          }

          Workspaces {  }
        }

        Clock {
          anchors.centerIn: parent
          active: root.openPopup === "calendar"
          onClicked: root.openPopup = root.openPopup === "calendar" ? "" : "calendar"
        }

        Buttons {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: 12
        }

        Popup {
          screen: root.screen
          barWindow: root
          open: root.openPopup === "calendar"
          barHeight: root.barHeight
          centerHorizontally: true
          // 32px more than CalendarDropdown.qml's own implicitWidth (660)
          // -- Popup.qml's fixed 16px-per-side content padding, same
          // contract as every other dropdown here.
          contentWidth: 692
          onCloseRequested: root.openPopup = ""

          CalendarDropdown {
            fgColor: root.fgColor
            mutedColor: root.mutedColor
            hoverColor: root.hoverColor
            colors: root.colors
            popupOpen: root.openPopup === "calendar"
            onCloseRequested: root.openPopup = ""
          }
        }

        Popup {
          screen: root.screen
          barWindow: root
          open: root.openPopup === "tray"
          barHeight: root.barHeight
          // Rough estimate, same caveat as every other rightMargin here:
          // Tray sits *before* Bluetooth in Buttons.qml with no divider
          // between them, so this is bluetooth's own 230 plus its icon-only
          // chip width (~30px, per that comment) plus Buttons.qml's 8px
          // RowLayout spacing. A single fixed position for the whole tray
          // group, not one that tracks the specific icon clicked -- with a
          // variable number of tray icons there's no fixed pixel offset
          // that could track a specific one anyway.
          rightMargin: 268
          // 260 clipped real menu text (Steam's "Steam Linux Runtime 1.0
          // (scout)" lost its closing paren) -- widened. Popup.qml's
          // contentWidth is the *whole* frame including its fixed 32px
          // side padding, so this leaves ~308px for row content, not 340.
          contentWidth: 340
          onCloseRequested: root.openPopup = ""

          TrayDropdown {
            fgColor: root.fgColor
            mutedColor: root.mutedColor
            hoverColor: root.hoverColor
            colors: root.colors
            trayItem: root.trayMenuItem
            onCloseRequested: root.openPopup = ""
          }
        }

        Popup {
          screen: root.screen
          barWindow: root
          open: root.openPopup === "power"
          barHeight: root.barHeight
          rightMargin: 8
          contentWidth: 470
          onCloseRequested: root.openPopup = ""

          PowerDropdown {
            fgColor: root.fgColor
            mutedColor: root.mutedColor
            hoverColor: root.hoverColor
            colors: root.colors
            onCloseRequested: root.openPopup = ""
          }
        }

        Popup {
          screen: root.screen
          barWindow: root
          open: root.openPopup === "bluetooth"
          barHeight: root.barHeight
          // Rough estimate of where the bluetooth button sits (it's not
          // the rightmost bar button, unlike power/battery, so this can't
          // just be a small fixed offset from the bar's right edge).
          // First guess (260) landed with the popup's right edge flush
          // against the button's *left* edge instead of under the
          // button -- short by roughly one button's width (icon-only, no
          // label, so just ~30px: 14px padding + ~16px glyph).
          rightMargin: 230
          contentWidth: 480
          onCloseRequested: root.openPopup = ""

          BluetoothDropdown {
            fgColor: root.fgColor
            mutedColor: root.mutedColor
            hoverColor: root.hoverColor
            colors: root.colors
            onCloseRequested: root.openPopup = ""
          }
        }

        Popup {
          screen: root.screen
          barWindow: root
          open: root.openPopup === "network"
          barHeight: root.barHeight
          // Same rough-estimate caveat as bluetooth's rightMargin above.
          // First guess (195) was short by another button-unit the same
          // way bluetooth's first guess was -- shifted right by one more
          // increment on top of that correction.
          rightMargin: 145
          contentWidth: 500
          onCloseRequested: root.openPopup = ""

          NetworkDropdown {
            fgColor: root.fgColor
            mutedColor: root.mutedColor
            hoverColor: root.hoverColor
            colors: root.colors
            popupOpen: root.openPopup === "network"
            onCloseRequested: root.openPopup = ""
          }
        }

        Popup {
          screen: root.screen
          barWindow: root
          open: root.openPopup === "audio"
          barHeight: root.barHeight
          // Same rough-estimate caveat as bluetooth/network above --
          // Volume sits between Network and Cpu in Buttons.qml, so this
          // should land somewhere short of network's 145, not yet
          // confirmed against the real bar.
          rightMargin: 90
          // Widened from the mock's 540 -- this machine's real ALSA
          // device names ("Radeon High Definition Audio Controller Pro
          // 7") run considerably longer than the mock's placeholder
          // names, and 540 wasn't leaving the name column enough room.
          contentWidth: 600
          onCloseRequested: root.openPopup = ""

          AudioDropdown {
            fgColor: root.fgColor
            mutedColor: root.mutedColor
            hoverColor: root.hoverColor
            colors: root.colors
            popupOpen: root.openPopup === "audio"
            onCloseRequested: root.openPopup = ""
          }
        }

        Popup {
          screen: root.screen
          barWindow: root
          open: root.openPopup === "system"
          barHeight: root.barHeight
          // Same rough-estimate caveat as every other dropdown above --
          // Cpu sits directly before Battery (the rightmost button) in
          // Buttons.qml, so this should be small, just enough to clear
          // Battery's own width, not yet confirmed against the real bar.
          rightMargin: 50
          // 32px more than SystemDropdown.qml's own implicitWidth (788)
          // -- that's Popup.qml's fixed 16px-per-side content padding,
          // not a separate number (see AudioDropdown's own header
          // comment for why getting this relationship wrong overflows
          // the window's own surface).
          contentWidth: 820
          onCloseRequested: root.openPopup = ""

          SystemDropdown {
            fgColor: root.fgColor
            mutedColor: root.mutedColor
            hoverColor: root.hoverColor
            colors: root.colors
            popupOpen: root.openPopup === "system"
            onCloseRequested: root.openPopup = ""
          }
        }
      }
    }
  }
}

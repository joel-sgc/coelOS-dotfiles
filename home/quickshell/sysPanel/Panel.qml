import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

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

        // Phase-1 plumbing check: the clock is the only button wired to a
        // real Popup so far (see Popup.qml) -- the other five still launch
        // their existing terminal tools (bluepala/netpala/pulsemixer/btop)
        // unchanged until their own phases replace that with inline
        // dropdowns. Only one popup open at a time will matter once more
        // of them exist; not needed yet with just this one.
        property bool calOpen: false

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

        RowLayout {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 14

          Logo {
            Layout.leftMargin: 12
          }

          Workspaces {  }
        }

        Clock {
          anchors.centerIn: parent
          active: root.calOpen
          onClicked: root.calOpen = !root.calOpen
        }

        Buttons {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: 12
        }

        Popup {
          screen: root.screen
          open: root.calOpen
          barHeight: root.barHeight
          centerHorizontally: true

          Text {
            text: "calendar (coming in a later phase)"
            color: root.fgColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
        }
      }
    }
  }
}

import Quickshell
import Quickshell.Hyprland
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
  property var colors: [
    "#61afef",  // Blue
    "#ef596f",  // Red
    "#e5c07b",  // Yellow
    "#89ca78",  // Green
    "#d55fde"   // Purple
  ]

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: root
        required property var modelData
        screen: modelData

        property var bgColor: panelScope.bgColor
        property var fgColor: panelScope.fgColor
        property var colors: panelScope.colors

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

        implicitHeight: 48
        color: root.bgColor

        RowLayout {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 16

          Logo {
            Layout.leftMargin: 16
          }

          Workspaces {  }
        }

        Clock {
          anchors.centerIn: parent
        }

        Buttons {
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: 16
        }
      }
    }
  }
}

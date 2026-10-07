import Quickshell
import Quickshell.Io
import QtQuick

import "./widgets"

// ===== DESKTOP WIDGETS =====
// Weather + calendar stacked on the left, kanban to their right, all on the
// first screen only (a widget duplicated across monitors would be two kanban
// boards editing the same file). Each widget is a layer-shell Bottom-layer
// window -- see widgets/DesktopWidget.qml. Colors live in widgets/Pal.qml.
//
// `quickshell ipc -p ~/.nixos/home/quickshell call widgets toggle` hides or
// shows all of them; `... call widgets newcard` opens the kanban editor.
Scope {
  id: root

  property int barHeight: 36
  property bool shown: true
  readonly property var screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  readonly property int top: barHeight + 24
  readonly property int left: 40
  readonly property int gap: 20

  IpcHandler {
    target: "widgets"
    function toggle(): void { root.shown = !root.shown; }
    function newcard(): void { kanban.openNew(0); }
  }

  Weather {
    id: weather
    screen: root.screen
    shown: root.shown
    marginTop: root.top
    marginLeft: root.left
  }

  Calendar {
    screen: root.screen
    shown: root.shown
    marginTop: weather.marginTop + weather.implicitHeight + root.gap
    marginLeft: root.left
  }

  Kanban {
    id: kanban
    screen: root.screen
    shown: root.shown
    marginTop: root.top
    anchorRight: true
    marginRight: root.left
  }
}

import Quickshell
import Quickshell.Io
import QtQuick

import "./widgets"

// ===== DESKTOP WIDGETS =====
// Weather + calendar stacked on the left, kanban to their right, all on the
// first screen only (a widget duplicated across monitors would be two kanban
// boards editing the same file). Each widget is a layer-shell Bottom-layer
// window -- see widgets/WidgetColumn.qml / WidgetCard.qml. Colors live in widgets/Pal.qml.
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

  // Weather + calendar share one window so the calendar slides up when the
  // weather card minimizes (see WidgetColumn.qml for why).
  WidgetColumn {
    screen: root.screen
    shown: root.shown
    marginTop: root.top
    marginLeft: root.left
    gap: root.gap

    Weather {}
    Calendar {}
  }

  Kanban {
    id: kanban
    screen: root.screen
    shown: root.shown
    marginTop: root.top
    marginRight: root.left
  }

  // Bottom right: pomodoro in the corner, server to its left. Separate
  // columns (the server is shorter, so it sits on the same bottom edge).
  WidgetColumn {
    screen: root.screen
    shown: root.shown
    anchorRight: true
    anchorBottom: true
    marginRight: root.left
    marginBottom: root.left

    Pomodoro { id: pomodoro }
  }

  WidgetColumn {
    screen: root.screen
    shown: root.shown
    anchorRight: true
    anchorBottom: true
    marginRight: root.left + pomodoro.cardWidth + root.gap
    marginBottom: root.left

    ServerStatus {}
  }
}

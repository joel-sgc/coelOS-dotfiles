import Quickshell
import Quickshell.Io
import QtQuick

import "./widgets"

// ===== DESKTOP WIDGETS =====
// Weather + calendar stacked on the left, kanban to their right, pomodoro and
// server status bottom right, on every monitor. The main screen's set
// (MainScreen.qml) is the primary one: it alone runs the pomodoro's timer
// events (finishing a session, the notification) and answers the IPC calls; the
// sets on the other monitors follow the same files (kanban.json, pomodoro.json,
// widgets.json, which all the widgets watch for changes) and can be used just the
// same. Each widget is a layer-shell Bottom-layer window -- see
// widgets/WidgetColumn.qml / WidgetCard.qml. Colors live in widgets/Pal.qml.
//
// `quickshell ipc -p ~/.nixos/home/quickshell call widgets toggle` hides or
// shows all of them; `... call widgets newcard` opens the kanban editor.
Scope {
  id: root

  property int barHeight: 36
  property bool shown: true
  readonly property var screen: MainScreen.screen
  readonly property int top: barHeight + 16
  readonly property int left: 16 + 4
  readonly property int gap: 20

  // The main screen's kanban, for `newcard`.
  property var mainKanban: null

  IpcHandler {
    target: "widgets"
    function toggle(): void { root.shown = !root.shown; }
    function newcard(): void { if (root.mainKanban) root.mainKanban.openNew(0); }
  }

  Variants {
    model: Quickshell.screens

    delegate: Scope {
      id: set
      required property var modelData
      readonly property bool primary: set.modelData === root.screen

      Binding { target: root; property: "mainKanban"; value: kanban; when: set.primary }

      // Weather + calendar share one window so the calendar slides up when the
      // weather card minimizes (see WidgetColumn.qml for why).
      WidgetColumn {
        screen: set.modelData
        shown: root.shown
        marginTop: root.top
        marginLeft: root.left
        gap: root.gap

        Weather {}
        Calendar {}
      }

      Kanban {
        id: kanban
        screen: set.modelData
        shown: root.shown
        marginTop: root.top
        marginRight: root.left
      }

      // Bottom right: pomodoro in the corner, server to its left. Separate
      // columns (the server is shorter, so it sits on the same bottom edge).
      WidgetColumn {
        screen: set.modelData
        shown: root.shown
        anchorRight: true
        anchorBottom: true
        marginRight: root.left
        marginBottom: root.left

        Pomodoro { id: pomodoro; primary: set.primary }
      }

      WidgetColumn {
        screen: set.modelData
        shown: root.shown
        anchorRight: true
        anchorBottom: true
        marginRight: root.left + pomodoro.cardWidth + root.gap
        marginBottom: root.left

        ServerStatus {}
      }
    }
  }
}

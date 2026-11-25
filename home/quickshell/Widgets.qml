import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
  // Border.qml's readyScreens: creating the widget windows only after the
  // border shadow's keeps them stacked above it (same layer).
  property var readyScreens: []
  readonly property var screen: MainScreen.screen
  // Outer gaps: the same general:gaps_out Hyprland puts around windows
  // (settings.toml [config.general]), re-read whenever the config reloads, so
  // the widgets sit exactly where a window's edge would. The panel's reserved
  // strip is added on top. Defaults match the built-in gaps until the first read.
  property int gapTop: 8
  property int gapRight: 12
  property int gapBottom: 12
  property int gapLeft: 12
  readonly property int top: barHeight + gapTop
  readonly property int left: gapLeft
  readonly property int right: gapRight
  readonly property int bottom: gapBottom
  readonly property int gap: 20

  Process {
    id: gapsProc
    command: ["hyprctl", "getoption", "general:gaps_out", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const v = String(JSON.parse(text).css).trim().split(/\s+/).map(Number);
          if (v.length === 1) v.push(v[0], v[0], v[0]);
          if (v.length !== 4 || v.some(isNaN)) return;
          root.gapTop = v[0]; root.gapRight = v[1];
          root.gapBottom = v[2]; root.gapLeft = v[3];
        } catch (e) {
          console.warn("widgets: could not read general:gaps_out:", e);
        }
      }
    }
  }
  Component.onCompleted: gapsProc.running = true
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") gapsProc.running = true;
    }
  }

  // The main screen's kanban, for `newcard`.
  property var mainKanban: null

  IpcHandler {
    target: "widgets"
    function toggle(): void { root.shown = !root.shown; }
    function newcard(): void { if (root.mainKanban) root.mainKanban.openNew(0); }
  }

  Variants {
    model: root.readyScreens

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
        marginRight: root.right
      }

      // Bottom right: pomodoro in the corner, server to its left. Separate
      // columns (the server is shorter, so it sits on the same bottom edge).
      WidgetColumn {
        screen: set.modelData
        shown: root.shown
        anchorRight: true
        anchorBottom: true
        marginRight: root.right
        marginBottom: root.bottom

        Pomodoro { id: pomodoro; primary: set.primary }
      }

      WidgetColumn {
        screen: set.modelData
        shown: root.shown
        anchorRight: true
        anchorBottom: true
        marginRight: root.right + pomodoro.cardWidth + root.gap
        marginBottom: root.bottom

        ServerStatus {}
      }
    }
  }
}

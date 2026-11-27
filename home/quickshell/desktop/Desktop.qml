import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."
import "../widgets"
import "data"

// The context-aware desktop (example/Desktop Board.dc.html): one DesktopScreen
// on the main screen for now (the second monitor's rail is phase 4), plus the
// kanban editor. `quickshell ipc -p ~/.nixos/home/quickshell call widgets
// toggle|newcard|day <n>|today`.
Scope {
  id: root
  property bool shown: true
  // Border.qml's readyScreens: creating these after the border keeps them above it.
  property var readyScreens: []
  property int barHeight: 36

  // Cards line up with tiled windows: the bar plus Hyprland's general:gaps_out
  // (settings.toml [config.general]), re-read whenever the config reloads. Cards
  // sit as far apart as they sit from the screen's sides (gaps_out's right).
  property var gaps: [8, 12, 12, 12]
  readonly property var edges: ({ top: barHeight + gaps[0], right: gaps[1], bottom: gaps[2], left: gaps[3], gap: gaps[1] })
  Process {
    id: gapsProc
    command: ["hyprctl", "getoption", "general:gaps_out", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const v = String(JSON.parse(text).css).trim().split(/\s+/).map(Number);
          while (v.length < 4) v.push(v[v.length - 1]);
          if (!v.some(isNaN)) root.gaps = v.slice(0, 4);
        } catch (e) { console.warn("desktop: could not read general:gaps_out:", e); }
      }
    }
  }
  Component.onCompleted: gapsProc.running = true
  Connections {
    target: Hyprland
    function onRawEvent(event) { if (event.name === "configreloaded") gapsProc.running = true; }
  }

  IpcHandler {
    target: "widgets"
    function toggle(): void { root.shown = !root.shown; }
    function newcard(): void { KanbanData.openNew(0); }
    // Move the desktop's selected day (calendar + next up): `day 1`, `day -7`, `today`.
    function day(n: int): void { CalendarData.shift(n); }
    function today(): void { CalendarData.goToday(); }
  }

  Variants {
    model: root.readyScreens.filter(s => s === MainScreen.screen)
    delegate: DesktopScreen {
      required property var modelData
      screen: modelData
      shown: root.shown
      edges: root.edges
    }
  }

  // The first-unlock-of-the-day greeting, on the main screen.
  // Login: continue from the login screen's picture (SessionIntro), then greet.
  SessionIntro { screen: MainScreen.screen }
  Greeting { screen: MainScreen.screen }

  // ----- kanban editor (one, on the main screen) -----
  property int editingId: -1
  Connections {
    target: KanbanData
    function onNewRequested(col) { root.editingId = -1; editor.openNew(col); }
    function onEditRequested(card, raw, col) { root.editingId = card.id; editor.openEdit(card, raw, col); }
  }
  KanbanEditor {
    id: editor
    screen: MainScreen.screen
    onSaved: (raw, notes, col) => {
      const p = KanbanData.parseTitle(raw);
      if (p.title === "") return;
      if (root.editingId === -1) KanbanData.addCard(col, p, notes);
      else KanbanData.updateCard(root.editingId, p, notes, col);
      editor.close();
    }
    onDeleted: { KanbanData.deleteCard(root.editingId); editor.close(); }
    onCancelled: editor.close()
  }
}

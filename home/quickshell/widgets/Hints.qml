import QtQuick

// Keybinding legend: [["h/l", "column"], ...] -> yellow key, muted label.
Flow {
  id: hints
  property var items: []
  spacing: 14
  Repeater {
    model: hints.items
    delegate: Row {
      required property var modelData
      spacing: 7
      Mono { text: modelData[0]; color: Pal.yellow }
      Mono { text: modelData[1]; color: Pal.muted }
    }
  }
}

import QtQuick

// ===== CORE ROW =====
// One per-core usage row in SystemDropdown.qml's cpu section -- label |
// mini bar | pct, in a column only ~134px wide (two of these sit
// side-by-side to make the 2x4 core grid). Manual anchors positioning,
// same reasoning as every other multi-column row in this codebase --
// and specifically NOT a RowLayout, since a RowLayout nested inside
// another RowLayout in this same section is exactly what broke on
// screen despite looking correct declaratively.
//
// A 10-segment bar, not the 20-segment one memory/disk rows use --
// this column is roughly half as wide, and a 20-char bar simply
// doesn't fit here.
Item {
  id: coreRoot

  property var core: ({ pct: 0 })
  property int coreIndex: 0
  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]

  implicitHeight: 16

  Text {
    id: coreLabel
    x: 0
    anchors.verticalCenter: parent.verticalCenter
    text: "c" + coreRoot.coreIndex
    color: coreRoot.mutedColor
    font.family: "JetBrains Mono"
    font.pixelSize: 12
  }
  Text {
    id: corePct
    anchors.right: parent.right
    width: 30
    horizontalAlignment: Text.AlignRight
    anchors.verticalCenter: parent.verticalCenter
    text: coreRoot.core.pct + "%"
    color: coreRoot.fgColor
    font.family: "JetBrains Mono"
    font.pixelSize: 12
  }
  Text {
    anchors.left: coreLabel.right
    anchors.leftMargin: 6
    anchors.right: corePct.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    readonly property int filled: Math.round(coreRoot.core.pct / 10)
    text: "█".repeat(filled)
    color: coreRoot.core.pct >= 75 ? coreRoot.colors[1] : coreRoot.core.pct >= 45 ? coreRoot.colors[2] : coreRoot.colors[3]
    font.family: "JetBrains Mono"
    font.pixelSize: 12
    Text { text: "░".repeat(10 - parent.filled); color: coreRoot.hoverColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
  }
}

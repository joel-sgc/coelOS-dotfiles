import "../.."
import QtQuick
import QtQuick.Layouts

// ===== WORKSPACE ROW INDICATOR =====
// From the bar mock (example/Quickshell Bar.dc.html): a vertical stack of small
// horizontal pips, one per row of the workspace grid, then an "r2"-style label
// and a thin divider before the workspace chips. The current row's pip is
// longest and takes the active workspace's colour; a row with
// windows open is medium and grey; an empty row is short and dim. Widths and
// colours ease between states. Display only: rows are changed with the keys and
// swipes (home/hyprland/hyprland.lua), so unlike the mock there are no arrows.
//
// Always five pips, even on the first row: the grid has exactly five rows
// (home/hyprland/grid.lua, ROWS).
Item {
  id: indicator

  readonly property int shown: 5   // the grid's row count (grid.lua ROWS)
  readonly property color accent: root.colors[(root.workspaceCol - 1) % root.colors.length]

  Layout.alignment: Qt.AlignVCenter
  Layout.rightMargin: 4
  implicitHeight: 26
  implicitWidth: contents.width + 1   // the 1 is the divider

  Row {
    id: contents
    height: parent.height
    spacing: 7
    leftPadding: 2
    rightPadding: 9

    // The pips: 20px wide, 26px tall, split evenly between the rows shown.
    Column {
      width: 20
      height: 26
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        model: indicator.shown

        delegate: Item {
          id: pipCell
          required property int index
          readonly property int rowIndex: index
          readonly property bool current: rowIndex === root.workspaceRow
          readonly property bool used: root.workspaceRowsInUse[rowIndex] === true

          width: 20
          height: 26 / indicator.shown

          Rectangle {
            id: pip
            anchors.verticalCenter: parent.verticalCenter
            x: 2
            height: 3
            radius: Globals.eyeCandyOff ? 0 : 2
            width: pipCell.current ? 16 : pipCell.used ? 10 : 6
            color: pipCell.current ? indicator.accent : pipCell.used ? "#5c6370" : "#3e4451"

            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }
          }
        }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "r" + (root.workspaceRow + 1)
      color: root.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 11
      font.letterSpacing: 0.3
      // At least two characters wide so "r9" -> "r10" does not shift the chips.
      width: Math.max(implicitWidth, 2 * font.pixelSize * 0.6)
    }
  }

  // Divider between the indicator and the workspace chips.
  Rectangle {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: 1
    height: 26
    color: "#3e4451"
  }
}

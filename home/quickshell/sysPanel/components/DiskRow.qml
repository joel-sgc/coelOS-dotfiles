import QtQuick

// ===== DISK ROW =====
// One mount entry in SystemDropdown.qml's disks section -- two lines,
// [mount+device · fstype | free-space] then [usage bar | used/total],
// with both lines sharing the same fixed right-column boundary so the
// free-space figures and used/total figures land in a real aligned
// column down the whole list instead of each row's own content pushing
// them around (RowLayout's fillWidth+natural-size did keep this
// *technically* right-aligned per row, but not as a fixed grid -- same
// reasoning as ProcessRow/DeviceRow/CoreRow for using manual positioning
// over a Layout for tabular data in this codebase).
Item {
  id: diskRoot

  property var disk: ({ mount: "", device: "", meta: "", usedGb: 0, totalGb: 1, freeGb: 0 })
  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  // Width of the fixed right-hand column (free-space text / used-total
  // text) -- both lines anchor to this same column so they line up.
  property int rightColWidth: 72
  property int rightColGap: 14

  readonly property int pct: Math.round(disk.usedGb / disk.totalGb * 100)
  readonly property color barColor: pct >= 85 ? colors[1] : pct >= 60 ? colors[2] : colors[3]
  // Free-space health, not usage-bar health -- separate scales on
  // purpose (a disk near its "normal" capacity isn't urgent the way one
  // with almost nothing left is; matches the mock's own d.freeColor
  // being red only on the one example disk that's genuinely nearly full).
  readonly property bool freeCritical: (disk.freeGb / disk.totalGb) < 0.02

  implicitHeight: line1.implicitHeight + line2.height + 1

  Text {
    id: line1
    x: 0
    y: 0
    width: parent.width - diskRoot.rightColWidth - diskRoot.rightColGap
    elide: Text.ElideRight
    textFormat: Text.StyledText
    text: "<font color='" + diskRoot.fgColor + "'>" + diskRoot.disk.mount + " " + diskRoot.disk.device + "</font> <font color='" + diskRoot.mutedColor + "'>· " + diskRoot.disk.meta + "</font>"
    font.family: "JetBrains Mono"
    font.pixelSize: 12
  }
  Text {
    anchors.right: parent.right
    anchors.verticalCenter: line1.verticalCenter
    width: diskRoot.rightColWidth
    horizontalAlignment: Text.AlignRight
    text: diskRoot.disk.freeGb.toFixed(1) + "G free"
    color: diskRoot.freeCritical ? diskRoot.colors[1] : diskRoot.mutedColor
    font.family: "JetBrains Mono"
    font.pixelSize: 12
  }

  Item {
    id: line2
    x: 0
    y: line1.implicitHeight + 1
    width: parent.width - diskRoot.rightColWidth - diskRoot.rightColGap
    height: 8
    Rectangle { anchors.fill: parent; radius: 1; color: "#353b45" }
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * (diskRoot.pct / 100)
      radius: 1
      color: diskRoot.barColor
    }
  }
  Text {
    anchors.right: parent.right
    anchors.verticalCenter: line2.verticalCenter
    width: diskRoot.rightColWidth
    horizontalAlignment: Text.AlignRight
    text: diskRoot.disk.usedGb.toFixed(0) + "/" + diskRoot.disk.totalGb.toFixed(0) + "G"
    color: diskRoot.mutedColor
    font.family: "JetBrains Mono"
    font.pixelSize: 12
  }
}

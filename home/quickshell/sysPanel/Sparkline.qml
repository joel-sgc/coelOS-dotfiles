import QtQuick
import QtQuick.Layouts

// ===== SPARKLINE =====
// Reusable bottom-aligned bar-chart column renderer, used by
// SystemDropdown.qml for the cpu/network history graphs -- the exact
// same RowLayout + Layout.alignment: Qt.AlignBottom shape
// PowerDropdown.qml's wattage history already proved out. A plain Row
// can't do this (it fights the delegate's own sizing for control of y
// at varying per-bar heights); RowLayout with per-item Layout.alignment
// doesn't have that fight.
Item {
  id: sparkRoot

  property var values: [] // 0..1 fractions, one per bar, oldest first
  property color barColor: "#89ca78"
  property real minOpacity: 1
  property real maxOpacity: 1

  RowLayout {
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: parent.height
    spacing: 1
    Repeater {
      model: sparkRoot.values
      delegate: Rectangle {
        required property real modelData
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(1, modelData * parent.height)
        Layout.alignment: Qt.AlignBottom
        radius: 1
        color: sparkRoot.barColor
        opacity: sparkRoot.minOpacity + modelData * (sparkRoot.maxOpacity - sparkRoot.minOpacity)
      }
    }
  }
}

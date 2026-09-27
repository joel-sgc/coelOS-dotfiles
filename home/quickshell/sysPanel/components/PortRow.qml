import QtQuick

// ===== PORT ROW =====
// One output/input port entry in AudioDropdown.qml's card settings panel
// -- a radio-select button plus name, greyed with an "unplugged" note
// when the port isn't currently available.
//
// Row can't have anchored children (see DeviceRow.qml's header comment
// for why), so the click target is a sibling of the Row inside this
// Item, not a child of the Row.
Item {
  id: portRoot

  required property var port // {dir, name, avail, active, hdmi?, headset?}
  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color accentColor: "#e5c07b"
  signal pick()

  implicitHeight: portRow.implicitHeight

  Row {
    id: portRow
    spacing: 8
    Text {
      text: portRoot.port.active ? "(•)" : "( )"
      color: portRoot.port.active ? portRoot.accentColor : portRoot.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
    }
    Text {
      text: portRoot.port.name
      color: portRoot.port.avail ? portRoot.fgColor : portRoot.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
    }
    Text {
      visible: !portRoot.port.avail
      text: "unplugged"
      color: portRoot.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 12
    }
  }
  MouseArea {
    anchors.fill: parent
    enabled: portRoot.port.avail
    cursorShape: Qt.PointingHandCursor
    onClicked: portRoot.pick()
  }
}

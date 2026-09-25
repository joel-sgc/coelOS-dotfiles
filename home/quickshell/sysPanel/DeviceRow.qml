import QtQuick
import "./Phosphor.js" as Phosphor

// ===== DEVICE ROW =====
// One sink/source row in AudioDropdown.qml's output/input sections --
// marker | radio(default) | name | volume-bar(click/drag) | pct | mute,
// plus a sub-line (node path, or why it's unavailable) when selected.
//
// Manual x/anchors positioning for the same reason as NetworkDropdown's
// network list and PowerDropdown's profile rows -- several fixed-width
// columns sharing one row is exactly the shape that broke under
// RowLayout before.
//
// The volume-bar/radio/mute-icon MouseAreas are declared *after* the
// row-select MouseArea in the same Item, so they naturally win any
// overlapping click (QML doesn't bubble mouse events between sibling
// MouseAreas by default -- whichever is on top in paint order absorbs
// the press) without needing the mock's explicit stopPropagation calls.
Column {
  id: rowRoot

  // Not `required` -- Column (this component's root) eagerly computes
  // its own implicit size from its children as soon as they're created,
  // which reads this property before the delegate's `row: modelData`
  // binding has settled. A real default shape (rather than leaving this
  // undefined) avoids a transient "Cannot read property of undefined"
  // during that first pass; the real value replaces it immediately after.
  property var row: ({ pwNode: null, mute: false, vol: 0, index: 0, av: true, name: "", isDefault: false, isSel: false, filled: 0, sub: "" })
  property string dir: "out" // "out" | "in"
  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]

  signal select()
  signal makeDefault()
  signal dragVolume(real fraction)
  signal toggleMute()

  spacing: 0

  Rectangle {
    id: rowItem
    width: parent.width
    height: 22
    radius: 2
    color: rowRoot.row.isSel ? "#2f343e" : (rowMouse.containsMouse ? "#2f343e" : "transparent")

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: rowRoot.select()
    }

    Text {
      id: marker
      x: 8
      width: 10
      anchors.verticalCenter: parent.verticalCenter
      text: rowRoot.row.isSel ? "▌" : ""
      color: rowRoot.colors[0]
      font.family: "JetBrains Mono"
      font.pixelSize: 13
    }
    Text {
      id: radioBtn
      x: marker.x + marker.width + 6
      anchors.verticalCenter: parent.verticalCenter
      text: rowRoot.row.isDefault ? "(•)" : "( )"
      color: rowRoot.row.isDefault ? rowRoot.colors[0] : rowRoot.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
      MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: { rowRoot.select(); rowRoot.makeDefault(); }
      }
    }

    Text {
      id: muteIcon
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      text: rowRoot.row.mute
        ? Phosphor.icon(rowRoot.dir === "out" ? "speaker-x" : "microphone-slash")
        : Phosphor.icon(rowRoot.dir === "out" ? "speaker-high" : "microphone")
      color: rowRoot.row.mute ? rowRoot.colors[1] : rowRoot.mutedColor
      font.family: "Phosphor"
      font.pixelSize: 13
      MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: rowRoot.toggleMute()
      }
    }
    Text {
      id: pct
      anchors.right: muteIcon.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      width: 32
      horizontalAlignment: Text.AlignRight
      text: rowRoot.row.av ? rowRoot.row.vol + "%" : "—"
      color: (rowRoot.row.mute || !rowRoot.row.av) ? rowRoot.mutedColor : rowRoot.fgColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
    }
    Item {
      id: volBar
      anchors.right: pct.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      width: 152
      height: 16

      Text {
        text: "░".repeat(20)
        color: "#404754"
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }
      Text {
        text: "█".repeat(rowRoot.row.filled)
        color: !rowRoot.row.av || rowRoot.row.mute ? rowRoot.mutedColor : rowRoot.row.isDefault ? rowRoot.colors[0] : rowRoot.fgColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }
      MouseArea {
        anchors.fill: parent
        enabled: rowRoot.row.av
        cursorShape: Qt.SizeHorCursor
        onPressed: (mouse) => rowRoot.dragVolume(Math.max(0, Math.min(1, mouse.x / width)))
        onPositionChanged: (mouse) => { if (pressed) rowRoot.dragVolume(Math.max(0, Math.min(1, mouse.x / width))); }
      }
    }
    Text {
      id: nameText
      x: radioBtn.x + 26
      anchors.right: volBar.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: rowRoot.row.name
      color: rowRoot.row.av ? rowRoot.fgColor : rowRoot.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
    }
  }

  Text {
    visible: rowRoot.row.isSel
    x: 46
    width: parent.width - 54
    elide: Text.ElideRight
    text: rowRoot.row.sub
    color: rowRoot.mutedColor
    font.family: "JetBrains Mono"
    font.pixelSize: 11
  }
}

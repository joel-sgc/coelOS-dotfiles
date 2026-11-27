import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import ".."
import "../widgets"

// The desktop card chrome (Desktop Board `card()`): rounded card with a header
// -- optional status dot and icon, title, "─ sub ─" (or the one-line summary
// while minimized), right-hand extras, a pin glyph when pinned, [–]/[+] -- and a
// body. Children land in the body; a minimized card is just its header.
Item {
  id: frame

  property string title: ""
  property string sub: ""
  property string summary: ""
  property string icon: ""
  property color tint: Pal.fg        // title/icon color (the mode's color on heroes)
  property color dot: "transparent"  // status dot before the title
  property bool minimized: false
  property bool pinned: false
  property bool focused: false
  property alias rightData: rightRow.data
  default property alias content: body.data

  signal minToggled()

  implicitWidth: 360
  implicitHeight: col.implicitHeight + (minimized ? 8 : 20)

  RectangularShadow {
    anchors.fill: bg
    radius: bg.radius
    offset.y: 18
    blur: 32
    spread: -12
    color: Qt.rgba(0, 0, 0, 0.5)
  }
  Rectangle {
    id: bg
    anchors.fill: parent
    radius: Globals.eyeCandyOff ? 0 : 16
    color: Pal.card
    border.width: 1
    border.color: frame.focused ? Pal.blue : Pal.faint
    Behavior on border.color { ColorAnimation { duration: Globals.eyeCandyOff ? 0 : 120 } }
  }

  ColumnLayout {
    id: col
    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 6 }
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 4
      Layout.bottomMargin: frame.minimized ? 4 : 8
      spacing: 8
      Rectangle {
        visible: frame.dot.a > 0
        Layout.preferredWidth: 7
        Layout.preferredHeight: 7
        radius: 3.5
        color: frame.dot
      }
      PhIcon { visible: frame.icon !== ""; name: frame.icon || "cpu"; color: frame.tint; font.pixelSize: 14 }
      Mono { text: frame.title; font.weight: Font.Medium; color: frame.focused ? Pal.blue : frame.tint }
      Mono {
        Layout.fillWidth: true
        text: frame.minimized ? frame.summary : (frame.sub !== "" ? "─ " + frame.sub + " ─" : "")
        color: frame.minimized ? Pal.dim : Pal.muted
        elide: Text.ElideRight
      }
      RowLayout { id: rightRow; visible: !frame.minimized; spacing: 6 }
      PhIcon { visible: frame.pinned; name: "push-pin"; fill: true; color: Pal.yellow; font.pixelSize: 12 }
      TextButton {
        hPad: 6
        onClicked: frame.minToggled()
        Mono { text: frame.minimized ? "[+]" : "[–]"; color: Pal.muted }
      }
    }

    ColumnLayout {
      id: body
      visible: !frame.minimized
      Layout.fillWidth: true
      spacing: 0
    }
  }
}

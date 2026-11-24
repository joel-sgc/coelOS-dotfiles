import QtQuick
import "../.."

// ===== ASSISTANT STATUS =====
// Discreet bubble next to the bell, driven by `coel-ask-screen` through
// Panel.qml's IpcHandler "assistant". Hidden while status is "idle".
//   working -> small pulsing dot
//   done    -> small green bubble holding just the (very short) answer
//   fail    -> small red dot
// Plain text only, no icon glyphs. Clicking dismisses it early.
Item {
  id: chip

  property string status: "idle"
  property string preview: ""
  signal dismissed()

  visible: status !== "idle"
  readonly property bool showText: status === "done" && preview.length > 0
  implicitWidth: visible ? (showText ? label.implicitWidth + 16 : 18) : 0
  implicitHeight: 20

  readonly property color accent: status === "done" ? root.colors[3]
    : status === "fail" ? root.colors[1] : root.colors[2]

  Rectangle {
    id: bubble
    anchors.centerIn: parent
    width: chip.showText ? parent.width : 10
    height: chip.showText ? parent.height : 10
    radius: height / 2
    color: chip.showText ? "transparent" : chip.accent
    border.width: chip.showText ? 1 : 0
    border.color: chip.accent

    SequentialAnimation on opacity {
      running: chip.status === "working"
      loops: Animation.Infinite
      onRunningChanged: if (!running) bubble.opacity = 1
      NumberAnimation { from: 1; to: 0.3; duration: 700 }
      NumberAnimation { from: 0.3; to: 1; duration: 700 }
    }
  }

  Text {
    id: label
    visible: chip.showText
    anchors.centerIn: parent
    font.family: "JetBrains Mono"
    font.pixelSize: 11
    color: root.fgColor
    textFormat: Text.PlainText
    text: chip.preview.length > 30 ? chip.preview.slice(0, 29) + "…" : chip.preview
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.dismissed()
  }
}

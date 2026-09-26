import QtQuick

// ===== PROCESS ROW =====
// One row in SystemDropdown.qml's process table -- marker | pid | name |
// user | threads | mem | cpu%, matching the mock's 7-column grid. Manual
// x/anchors positioning (anchor chain from the right for the numeric
// columns), same reasoning as DeviceRow.qml/PowerDropdown's profile
// rows -- several fixed-width columns sharing one row is exactly the
// shape RowLayout has broken on before in this codebase.
Rectangle {
  id: procRoot

  // Not `required` -- see DeviceRow.qml's comment on why a plain Item/
  // Rectangle root still benefits from a real default shape rather than
  // leaving this undefined during the delegate's first construction pass.
  property var row: ({ pid: 0, name: "", user: "", thr: 0, mem: "", cpu: 0, isSel: false })
  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color accentColor: "#61afef"

  signal select()
  signal kill()

  width: parent.width
  height: 20
  radius: 2
  color: row.isSel ? "#2f343e" : (rowMouse.containsMouse ? "#2f343e" : "transparent")

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: procRoot.select()
    onDoubleClicked: procRoot.kill()
  }

  Text {
    id: marker
    x: 8
    width: 10
    anchors.verticalCenter: parent.verticalCenter
    text: procRoot.row.isSel ? "▌" : ""
    color: procRoot.accentColor
    font.family: "JetBrains Mono"
    font.pixelSize: 13
  }
  Text {
    id: pidText
    x: marker.x + marker.width + 4
    width: 44
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    text: String(procRoot.row.pid)
    color: procRoot.mutedColor
    font.family: "JetBrains Mono"
    font.pixelSize: 13
  }

  Text {
    id: cpuText
    anchors.right: parent.right
    anchors.rightMargin: 8
    width: 42
    horizontalAlignment: Text.AlignRight
    anchors.verticalCenter: parent.verticalCenter
    text: procRoot.row.cpu.toFixed(1) + "%"
    color: procRoot.row.cpu >= 50 ? "#ef596f" : procRoot.row.cpu >= 15 ? "#e5c07b" : procRoot.fgColor
    font.family: "JetBrains Mono"
    font.pixelSize: 13
  }
  Text {
    id: memText
    anchors.right: cpuText.left
    anchors.rightMargin: 8
    width: 48
    horizontalAlignment: Text.AlignRight
    anchors.verticalCenter: parent.verticalCenter
    text: procRoot.row.mem
    color: procRoot.fgColor
    font.family: "JetBrains Mono"
    font.pixelSize: 13
  }
  Text {
    id: thrText
    anchors.right: memText.left
    anchors.rightMargin: 8
    width: 26
    horizontalAlignment: Text.AlignRight
    anchors.verticalCenter: parent.verticalCenter
    text: String(procRoot.row.thr)
    color: procRoot.mutedColor
    font.family: "JetBrains Mono"
    font.pixelSize: 13
  }
  Text {
    id: userText
    anchors.right: thrText.left
    anchors.rightMargin: 8
    width: 52
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: procRoot.row.user
    color: procRoot.mutedColor
    font.family: "JetBrains Mono"
    font.pixelSize: 13
  }
  Text {
    id: nameText
    x: pidText.x + pidText.width + 8
    anchors.right: userText.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: procRoot.row.name
    color: procRoot.fgColor
    font.family: "JetBrains Mono"
    font.pixelSize: 13
  }
}

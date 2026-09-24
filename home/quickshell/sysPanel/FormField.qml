import QtQuick
import QtQuick.Layouts

// ===== FORM FIELD =====
// The "130px label | editor" row NetworkDropdown.qml's edit/hotspot forms
// use repeatedly -- either a text input (mode: "text"/"password") or a
// click-to-cycle-through-options control (mode: "cycle").
//
// RowLayout is safe for this specific shape -- one fixed-width label plus
// one fillWidth value area, nothing else. The RowLayout misalignment bug
// found in PowerDropdown.qml's profile rows was specifically about many
// mixed fixed/natural-width columns fighting over the same row; several
// already-working rows elsewhere in this codebase (Cpu.qml's button
// label, PowerDropdown's brightness row) use this same simple two-item
// shape without issue.
RowLayout {
  id: fieldRoot

  property string label: ""
  property color labelColor: "#5c6370"
  property color fgColor: "#abb2bf"
  property color accentColor: "#61afef"
  property color hoverColor: "#404754"
  property int labelWidth: 130

  // "text" | "password" | "cycle"
  property string mode: "text"
  property string value: ""
  property string placeholder: ""
  property bool fieldEnabled: true
  // Shows a "[show]"/"[hide]" button in the input's corner -- the field
  // itself doesn't own the shown/hidden state (the caller does, by
  // switching `mode` between "text" and "password"), this just gives it
  // something clickable to flip that with instead of dots you're stuck
  // looking at forever.
  property bool showToggle: false
  signal valueEdited(string newValue)
  signal cycled()
  signal toggleVisibility()
  // TextInput accepts/consumes Return itself rather than letting it
  // bubble up to a container's Keys.onPressed, so a caller that wants
  // "press enter to submit" (NetworkDropdown.qml's edit view) needs this
  // forwarded explicitly rather than relying on event propagation.
  signal accepted()

  Layout.fillWidth: true
  height: 22
  spacing: 12

  Text {
    Layout.preferredWidth: fieldRoot.labelWidth
    text: fieldRoot.label
    color: fieldRoot.labelColor
    font.family: "JetBrains Mono"
    font.pixelSize: 13
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 20
    visible: fieldRoot.mode !== "cycle"

    Rectangle {
      anchors.fill: parent
      color: textInput.activeFocus ? "#2c313c" : "#1e2127"
    }
    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: textInput.activeFocus ? fieldRoot.accentColor : fieldRoot.hoverColor
    }
    TextInput {
      id: textInput
      anchors.left: parent.left
      anchors.right: toggleLabel.visible ? toggleLabel.left : parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.leftMargin: 6
      anchors.rightMargin: 6
      verticalAlignment: TextInput.AlignVCenter
      text: fieldRoot.value
      echoMode: fieldRoot.mode === "password" ? TextInput.Password : TextInput.Normal
      color: fieldRoot.fgColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
      enabled: fieldRoot.fieldEnabled
      selectByMouse: true
      onTextEdited: fieldRoot.valueEdited(text)
      onAccepted: fieldRoot.accepted()
    }
    Text {
      visible: fieldRoot.placeholder.length > 0 && fieldRoot.value.length === 0 && !textInput.activeFocus
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.right: toggleLabel.visible ? toggleLabel.left : parent.right
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: fieldRoot.placeholder
      color: fieldRoot.labelColor
      font.family: "JetBrains Mono"
      font.italic: true
      font.pixelSize: 12
    }
    Text {
      id: toggleLabel
      visible: fieldRoot.showToggle && (fieldRoot.mode === "password" || fieldRoot.mode === "text")
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      text: fieldRoot.mode === "password" ? "[show]" : "[hide]"
      color: toggleMouse.containsMouse ? fieldRoot.accentColor : fieldRoot.labelColor
      font.family: "JetBrains Mono"
      font.pixelSize: 12
      MouseArea {
        id: toggleMouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: fieldRoot.toggleVisibility()
      }
    }
  }

  Item {
    // Row doesn't allow anchored children (it positions them itself via
    // x/y), so the click target here is a sibling of the Row inside
    // this Item, not a child of the Row.
    Layout.fillWidth: true
    Layout.preferredHeight: 20
    visible: fieldRoot.mode === "cycle"
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6
      Text { text: "‹"; color: fieldRoot.hoverColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
      Text { text: fieldRoot.value; color: fieldRoot.fieldEnabled ? fieldRoot.fgColor : fieldRoot.labelColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
      Text { text: "›"; color: fieldRoot.hoverColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
    }
    MouseArea {
      anchors.fill: parent
      enabled: fieldRoot.fieldEnabled
      cursorShape: Qt.PointingHandCursor
      onClicked: fieldRoot.cycled()
    }
  }
}

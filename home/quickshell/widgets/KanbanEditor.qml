import Quickshell
import ".."
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// ===== KANBAN CARD EDITOR (modal) =====
// A full-screen Overlay window with exclusive keyboard focus: dimmed scrim
// plus the dialog. Lives in its own window because the desktop widget layer
// can't be relied on for text entry. Click the scrim or press Esc to cancel,
// Enter (title) / Ctrl+Enter (notes) to save, Alt+1..3 picks the state.
PanelWindow {
  id: root

  readonly property var states: [
    { label: "todo", color: Pal.fg },
    { label: "doing", color: Pal.yellow },
    { label: "done", color: Pal.green }
  ]

  property bool shown: false
  property bool isNew: true
  property int state: 0
  property string field: "title"

  signal saved(string rawTitle, string notes, int col)
  signal deleted()
  signal cancelled()

  function openNew(col) {
    isNew = true; state = col;
    titleInput.text = ""; notesInput.text = "";
    open();
  }
  function openEdit(card, rawTitle, col) {
    isNew = false; state = col;
    titleInput.text = rawTitle; notesInput.text = card.notes || "";
    open();
  }
  function open() { field = "title"; shown = true; }
  function close() { shown = false; }
  readonly property bool canSave: titleInput.text.trim() !== ""
  function trySave() {
    if (canSave) root.saved(titleInput.text, notesInput.text.trim(), root.state);
    else titleInput.forceActiveFocus();
  }
  function handleShortcuts(e) {
    if (e.key === Qt.Key_Escape) { root.cancelled(); e.accepted = true; }
    else if ((e.modifiers & Qt.AltModifier) && e.key >= Qt.Key_1 && e.key <= Qt.Key_3) {
      root.state = e.key - Qt.Key_1; e.accepted = true;
    }
  }

  visible: shown
  onVisibleChanged: if (visible) titleInput.forceActiveFocus()

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "coel-kanban-editor"

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.55)
    MouseArea { anchors.fill: parent; onClicked: root.cancelled() }
  }

  Rectangle {
    id: dialog
    width: 520
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    height: dialogCol.implicitHeight + 20
    radius: Globals.eyeCandyOff ? 0 : 16
    color: Pal.card
    border.width: 1
    border.color: Pal.faint

    // swallow clicks so they don't fall through to the scrim
    MouseArea { anchors.fill: parent }

    ColumnLayout {
      id: dialogCol
      anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 10 }
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        spacing: 8
        Mono { text: root.isNew ? "new card" : "edit card"; font.weight: Font.Medium; color: Pal.blue }
        Mono { text: "─ ~/dots/shell ─"; color: Pal.muted }
        Mono { text: root.states[root.state].label; color: root.states[root.state].color }
        Item { Layout.fillWidth: true }
        TextButton {
          visible: !root.isNew
          hoverColor: Pal.faint
          onClicked: root.deleted()
          Mono { text: "x"; color: Pal.red }
          Mono { text: "delete"; color: Pal.muted }
        }
        TextButton {
          onClicked: root.cancelled()
          Mono { text: "[×]"; color: parent.parent.hovered ? Pal.red : Pal.muted }
        }
      }

      // title
      Box {
        Layout.fillWidth: true
        Layout.topMargin: 8
        padTop: 14; padSide: 10; padBottom: 10
        legend: "title"; legendColor: root.field === "title" ? Pal.blue : Pal.muted
        rightLegend: "required"
        borderColor: root.field === "title" ? Pal.blue : Pal.faint

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: titleInput.implicitHeight + 8
          color: titleInput.activeFocus ? Pal.raised : Pal.deep
          Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: titleInput.activeFocus ? Pal.blue : Pal.faint
          }
          TextInput {
            id: titleInput
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            font.family: Pal.mono; font.pixelSize: 12
            color: Pal.fg
            selectionColor: Pal.blue
            selectedTextColor: Pal.card
            clip: true
            onActiveFocusChanged: if (activeFocus) root.field = "title"
            KeyNavigation.tab: notesInput
            Keys.onReturnPressed: root.trySave()
            Keys.onEnterPressed: root.trySave()
            Keys.onPressed: (e) => root.handleShortcuts(e)
          }
          Mono {
            visible: titleInput.text === ""
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
            text: "what needs doing  ·  !high  #tag  @fri"
            color: Pal.muted
          }
        }
      }

      // notes
      Box {
        Layout.fillWidth: true
        Layout.topMargin: 16
        padTop: 14; padSide: 10; padBottom: 10
        legend: "notes"; legendColor: root.field === "notes" ? Pal.blue : Pal.muted
        rightLegend: "optional"
        borderColor: root.field === "notes" ? Pal.blue : Pal.faint

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 84
          color: notesInput.activeFocus ? Pal.raised : Pal.deep
          Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: notesInput.activeFocus ? Pal.blue : Pal.faint
          }
          TextEdit {
            id: notesInput
            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 4; bottomMargin: 4 }
            wrapMode: TextEdit.Wrap
            font.family: Pal.mono; font.pixelSize: 12
            color: Pal.fg
            selectionColor: Pal.blue
            selectedTextColor: Pal.card
            clip: true
            onActiveFocusChanged: if (activeFocus) root.field = "notes"
            KeyNavigation.tab: titleInput
            Keys.onPressed: (e) => {
              if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) {
                root.trySave();
                e.accepted = true;
              } else root.handleShortcuts(e);
            }
          }
          Mono {
            visible: notesInput.text === ""
            anchors { top: parent.top; left: parent.left; topMargin: 4; leftMargin: 8 }
            text: "description, links, steps…"
            color: Pal.muted
          }
        }
      }

      // state
      Box {
        Layout.fillWidth: true
        Layout.topMargin: 16
        padTop: 14; padSide: 6; padBottom: 8
        legend: "state"

        Flow {
          Layout.fillWidth: true
          spacing: 16
          Repeater {
            model: root.states
            delegate: TextButton {
              required property var modelData
              required property int index
              readonly property bool picked: root.state === index
              hPad: 6
              color: picked ? Pal.edge : (hovered ? Pal.edge : "transparent")
              onClicked: root.state = index
              Mono { text: picked ? "(•)" : "( )"; color: picked ? modelData.color : Pal.muted }
              Mono { text: modelData.label; color: picked ? Pal.fg : Pal.dim }
              Mono { text: "alt " + (index + 1); color: Pal.muted }
            }
          }
        }
      }

      // footer
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 14
        spacing: 12
        Hints {
          Layout.fillWidth: true
          items: [["⏎", "add"], ["ctrl ⏎", "add from notes"], ["alt 1-3", "state"], ["esc", "cancel"]]
        }
        Rectangle {
          Layout.alignment: Qt.AlignTop
          Layout.preferredWidth: addText.implicitWidth + 20
          Layout.preferredHeight: addText.implicitHeight
          radius: Globals.eyeCandyOff ? 0 : 2
          color: root.canSave ? Pal.green : Pal.muted
          opacity: root.canSave ? 1 : 0.45
          Mono {
            id: addText
            anchors.centerIn: parent
            text: root.isNew ? "< add card >" : "< save card >"
            font.weight: Font.Medium
            color: Pal.card
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.trySave()
          }
        }
      }
    }
  }
}

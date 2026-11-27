import QtQuick
import QtQuick.Layouts
import ".."
import "../widgets"
import "../modes"

// The mode override menu (Desktop Board `modeMenu`), under the mode chip.
// Keys: 1–7 pick, a back to auto, k cycles how long a pick holds, esc / M close.
CardFrame {
  id: menu
  signal closeRequested()

  title: "mode"
  sub: "override"
  focused: true
  implicitWidth: 420

  readonly property var keeps: [["event", "until the next event"], ["hour", "for 1 hour"], ["forever", "until I change it"]]

  function handleKey(e) {
    const t = e.text;
    if (e.key === Qt.Key_Escape || t === "M") { closeRequested(); return true; }
    if (t === "a") { Modes.set("auto"); return true; }
    if (t === "k") { const i = keeps.findIndex(k => k[0] === Modes.keep); Modes.keep = keeps[(i + 1) % keeps.length][0]; return true; }
    const n = parseInt(t);
    if (n >= 1 && n <= Modes.order.length) { Modes.set(Modes.order[n - 1]); return true; }
    return false;
  }
  onMinToggled: closeRequested()

  component Radio: Mono {
    property bool on: false
    property color tintOn: Pal.blue
    text: on ? "(•)" : "( )"
    color: on ? tintOn : Pal.muted
  }

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: autoRow.implicitHeight + 6
    radius: 2
    color: autoArea.containsMouse ? Pal.edge : "transparent"
    RowLayout {
      id: autoRow
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
      spacing: 8
      Radio { Layout.preferredWidth: 28; on: !Modes.manual; tintOn: Pal.green }
      Mono { text: "auto" }
      Mono {
        Layout.fillWidth: true
        text: "· " + Modes.labelOf(Modes.inferred) + (Modes.whyOf(Modes.inferred) ? ", because " + Modes.whyOf(Modes.inferred) : "")
        color: Pal.muted
        elide: Text.ElideRight
      }
    }
    MouseArea { id: autoArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Modes.set("auto") }
  }
  Rectangle { Layout.fillWidth: true; Layout.topMargin: 6; Layout.bottomMargin: 6; implicitHeight: 1; color: Pal.faint }

  Repeater {
    model: Modes.order
    Rectangle {
      id: modeRow
      required property var modelData
      required property int index
      readonly property bool on: Modes.manual && Modes.mode === modelData
      Layout.fillWidth: true
      implicitHeight: mrow.implicitHeight + 6
      radius: 2
      color: on ? Pal.faint : area.containsMouse ? Pal.edge : "transparent"
      Row {
        id: mrow
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
        spacing: 8
        Radio { width: 28; on: modeRow.on; tintOn: Modes.info[modeRow.modelData].color }
        PhIcon { width: 18; name: Modes.info[modeRow.modelData].icon; color: Modes.info[modeRow.modelData].color; font.pixelSize: 13 }
        Mono { width: 92; text: Modes.info[modeRow.modelData].label }
        Mono { visible: Modes.inferred === modeRow.modelData; text: "← auto picks this now"; color: Pal.muted }
      }
      Mono {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 8 }
        text: String(modeRow.index + 1)
        color: Pal.yellow
      }
      MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Modes.set(modeRow.modelData) }
    }
  }

  Box {
    Layout.fillWidth: true
    Layout.topMargin: 16
    padTop: 12; padSide: 12; padBottom: 8
    legend: "keep an override"
    Flow {
      Layout.fillWidth: true
      spacing: 14
      Repeater {
        model: menu.keeps
        Row {
          required property var modelData
          spacing: 6
          Radio { on: Modes.keep === parent.modelData[0] }
          Mono { text: parent.modelData[1]; color: Modes.keep === parent.modelData[0] ? Pal.fg : Pal.muted }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: Modes.keep = parent.modelData[0] }
        }
      }
    }
  }
  Hints {
    Layout.fillWidth: true
    Layout.topMargin: 12
    items: [["M", "open"], ["1–7", "pick"], ["a", "back to auto"], ["k", "keep"], ["esc", "close"]]
  }
}

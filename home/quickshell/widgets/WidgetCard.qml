import ".."
import QtQuick
import QtQuick.Layouts

// ===== WIDGET CARD =====
// One desktop widget: a rounded card with a header (title, subtitle, buttons,
// [-]/[+] minimize toggle) and a body. Children declared inside a card land
// in the body ColumnLayout and are hidden while minimized. Cards live inside a
// WidgetColumn (the layer-shell window), which stacks them -- so a card
// minimizing just changes layout and the cards below slide up with it.
//
// Keyboard: clicking a card gives it focus (the column window takes keys on
// demand); `focused` drives the brighter border / blue title, and key presses
// arrive through keyPressed (hjkl and friends -- see each widget).
FocusScope {
  id: card

  property int cardWidth: 360
  readonly property bool focused: card.activeFocus && card.Window.active
  default property alias content: body.data

  // Header + minimize. Each widget names itself and fills in what the header
  // shows; the base class builds the row and the [-]/[+] toggle, and hides
  // everything declared inside the widget while minimized.
  //   title      bold name (blue when focused)
  //   subtitle   "-- place --" text, only while open
  //   summary    one-line status shown instead of the subtitle while minimized
  //   summaryAlways / summaryColor   kanban keeps its tally visible when open
  //   icon       optional Phosphor icon before the title
  //   headerData extra right-hand header items (buttons, bars), open only
  property string widgetId: ""
  property string title: ""
  property string subtitle: ""
  property string summary: ""
  property bool summaryAlways: false
  property color summaryColor: Pal.dim
  property string icon: ""
  property alias headerData: headerExtra.data
  readonly property bool minimized: widgetId !== "" && WidgetState.isMin(widgetId)

  signal keyPressed(var event)

  // 0 = minimized, 1 = open; animated so the body slides shut and the cards
  // below follow smoothly (the window is a fixed strip, see WidgetColumn.qml).
  property real reveal: minimized ? 0 : 1
  Behavior on reveal {
    NumberAnimation { duration: Globals.eyeCandyOff ? 0 : 200; easing.type: Easing.OutCubic }
  }

  Layout.fillWidth: true
  implicitWidth: card.cardWidth
  implicitHeight: outer.implicitHeight + 20
  Keys.onPressed: (e) => card.keyPressed(e)

  Rectangle {
    anchors.fill: parent
    radius: Globals.eyeCandyOff ? 0 : 16
    color: Pal.card
    border.width: 1
    border.color: card.focused ? Pal.faint : Pal.edge
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    onPressedChanged: if (pressed) card.forceActiveFocus()
  }

    ColumnLayout {
      id: outer
      anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 10 }
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 8 * card.reveal
        spacing: 8
        PhIcon { visible: card.icon !== ""; name: card.icon !== "" ? card.icon : "cpu"; color: card.focused ? Pal.blue : Pal.dim; font.pixelSize: 14 }
        Mono { text: card.title; font.weight: Font.Medium; color: card.focused ? Pal.blue : Pal.dim }
        Mono {
          visible: !card.minimized && card.subtitle !== ""
          Layout.fillWidth: !card.summaryAlways
          text: "─ " + card.subtitle + " ─"
          color: Pal.muted
          elide: Text.ElideRight
        }
        Mono {
          visible: card.minimized || card.summaryAlways
          Layout.fillWidth: card.minimized
          text: card.summary
          color: card.summaryAlways ? card.summaryColor : Pal.dim
          elide: Text.ElideRight
        }
        Item { visible: !card.minimized && (card.subtitle === "" || card.summaryAlways); Layout.fillWidth: true }
        RowLayout {
          id: headerExtra
          visible: !card.minimized
          opacity: card.reveal
          spacing: 6
        }
        TextButton {
          visible: card.widgetId !== ""
          onClicked: WidgetState.toggle(card.widgetId)
          Mono { text: card.minimized ? "[+]" : "[–]"; color: Pal.muted }
        }
      }

      Item {
        id: clipBox
        visible: card.reveal > 0
        // Boxes draw their legend above their top edge, so the clip region
        // starts 12px above the body: pulled up by the negative margin, with
        // the body pushed back down by the same amount.
        clip: true
        Layout.topMargin: -12
        Layout.fillWidth: true
        Layout.preferredHeight: (body.implicitHeight + 12) * card.reveal

        ColumnLayout {
          id: body
          anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 12 }
          opacity: card.reveal
          spacing: 0
        }
      }
    }
}

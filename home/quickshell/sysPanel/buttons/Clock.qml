import QtQuick

// ===== CLOCK =====
// Same format as waybar's clock module ({:L%A @ %I:%M %p}) -- Qt's own
// format tokens (dddd/hh/mm/AP) do this natively via Qt.formatDateTime,
// no manual strftime-style parsing needed. Re-reads Date.now() every 30s;
// no seconds shown, so that's plenty granular without a 1s timer running
// forever. Emits clicked() for Panel.qml to toggle the calendar Popup --
// the calendar's own content isn't built yet (that's a later phase), this
// just wires the button through.
//
// Now a proper chip (padded background, radius 6) matching the mock,
// rather than bare text -- `active` is set true while the calendar popup
// is open, so the button stays highlighted the whole time it's open, not
// just on hover, same as {{ clockBg }} in the mock.
Item {
  id: clockRoot

  property bool active: false
  signal clicked()

  implicitWidth: label.implicitWidth + 24
  implicitHeight: 26

  function refresh() {
    label.text = Qt.formatDateTime(new Date(), "dddd @ hh:mm AP");
  }

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: (clockRoot.active || mouseArea.containsMouse) ? root.hoverColor : "transparent"
  }

  Text {
    id: label
    anchors.centerIn: parent
    color: root.fgColor
    font.family: "JetBrains Mono"
    font.pixelSize: 14
    font.letterSpacing: 0.3
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: clockRoot.refresh()
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: clockRoot.clicked()
  }
}

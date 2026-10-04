import QtQuick

import "../Phosphor.js" as Phosphor

// ===== BELL =====
// Standalone notifications button, next to Clock -- not one of Buttons.qml's
// grouped row, matching the design mock's own layout (the bell sits right
// next to the clock chip, not with bluetooth/network/audio/etc). Same
// structural template as Clock.qml (bare Item, own background Rectangle,
// own clicked() signal) rather than the shared Button.qml component, for
// the same reason Clock.qml isn't: this needs its own badge overlay, which
// Button.qml's fixed icon+label RowLayout has no slot for.
//
// unreadCount/dnd are driven by Panel.qml from root.notifications (the real
// NotificationsBackend) -- this file itself has no knowledge of the backend,
// same props-down shape as every other bar button here.
Item {
  id: bellRoot

  property bool active: false
  property int unreadCount: 0
  property bool dnd: false
  signal clicked()

  // Grows with the badge instead of a flat 34 -- that clipped a real
  // double-digit unread count (confirmed live, 14 unread rendered
  // overlapping the icon) since it never accounted for the label actually
  // getting wider.
  implicitWidth: Math.max(34, badgeRow.implicitWidth + 14)
  implicitHeight: 26

  function bellIcon() {
    if (dnd) return Phosphor.icon("bell-simple-slash");
    if (unreadCount > 0) return Phosphor.icon("bell-simple-ringing");
    return Phosphor.icon("bell-simple");
  }

  Rectangle {
    anchors.fill: parent
    radius: 5
    color: (bellRoot.active || mouseArea.containsMouse) ? root.hoverColor : "transparent"
  }

  Row {
    id: badgeRow
    anchors.centerIn: parent
    spacing: 5

    Text {
      text: bellRoot.bellIcon()
      color: bellRoot.dnd ? root.mutedColor : root.fgColor
      font.family: "Phosphor"
      font.pixelSize: 14
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: bellRoot.unreadCount > 0
      // The real count, not capped at "9+" -- the button now widens to
      // fit it instead (see implicitWidth above).
      text: String(bellRoot.unreadCount)
      color: root.colors[2]
      font.family: "JetBrains Mono"
      font.pixelSize: 12
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: bellRoot.clicked()
  }
}

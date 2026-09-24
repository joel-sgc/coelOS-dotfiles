import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// ===== TRAY =====
// Ported from home/waybar.nix's group/tray-expander -- no expand/collapse
// drawer here (that was purely a "hide icons behind a caret" space-saving
// trick, not core behavior), just every registered StatusNotifierItem laid
// out plainly. Left click activates the item (its usual primary action);
// right click calls secondaryActivate() -- most tray apps treat that as
// "open the menu", though there's no real DBusMenu popup wired up here
// (that's a genuinely new widget, out of scope for "a few buttons").
//
// Chip chrome (26px, radius 5, hover background, dim-until-hovered color)
// and the trailing separator both match the mock exactly -- 2px between
// icons, 8px before the divider, 4px after it. The separator reuses
// root.hoverColor rather than a hardcoded hex: the mock's border-right and
// its hover background are the same #404754, not a coincidence worth
// duplicating as a second magic value.
RowLayout {
  spacing: 2

  Repeater {
    model: SystemTray.items

    delegate: Item {
      id: trayItem
      required property var modelData

      implicitWidth: 26
      implicitHeight: 26

      Rectangle {
        anchors.fill: parent
        radius: 5
        color: trayMouseArea.containsMouse ? root.hoverColor : "transparent"
      }

      IconImage {
        anchors.centerIn: parent
        source: trayItem.modelData.icon
        implicitSize: 16
      }

      MouseArea {
        id: trayMouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
          if (mouse.button === Qt.RightButton) {
            trayItem.modelData.secondaryActivate();
          } else {
            trayItem.modelData.activate();
          }
        }
      }
    }
  }

  Rectangle {
    visible: SystemTray.items.values.length > 0
    Layout.preferredWidth: 1
    Layout.fillHeight: true
    Layout.topMargin: 4
    Layout.bottomMargin: 4
    Layout.leftMargin: 8
    Layout.rightMargin: 4
    color: root.hoverColor
  }
}

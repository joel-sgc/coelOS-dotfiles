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
RowLayout {
  spacing: 8

  Repeater {
    model: SystemTray.items

    delegate: IconImage {
      id: trayIcon
      required property var modelData

      source: modelData.icon
      implicitSize: 18

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
          if (mouse.button === Qt.RightButton) {
            trayIcon.modelData.secondaryActivate();
          } else {
            trayIcon.modelData.activate();
          }
        }
      }
    }
  }
}

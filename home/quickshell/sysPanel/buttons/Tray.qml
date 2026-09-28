import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// ===== TRAY =====
// Ported from home/waybar.nix's group/tray-expander -- no expand/collapse
// drawer here (that was purely a "hide icons behind a caret" space-saving
// trick, not core behavior), just every registered StatusNotifierItem laid
// out plainly. Left click activates the item (its usual primary action);
// right click opens the item's real DBusMenu when it has one -- most tray
// apps (NetworkManager, audio mixers, etc.) only populate their actual
// menu on secondaryActivate/right click, not on the primary activate().
// Falls back to secondaryActivate() for the few apps with no real menu
// (hasMenu false) -- some tray icons only ever respond to that directly.
//
// The menu itself is TrayDropdown.qml (sysPanel/dropdowns), a real
// Popup.qml-chrome dropdown like every other bar button here -- not
// QsMenuAnchor's native platform popup (tried first: needs `//@ pragma
// UseQApplication` + a full quickshell restart just to call .open(), and
// even then opened flush against the very top of the screen, blocking
// everything, with none of this panel's own styling). root.trayMenuItem
// (Panel.qml) carries which SystemTrayItem was right-clicked over to that
// shared dropdown, since a single Popup instance is reused for every tray
// icon rather than giving each one its own.
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
            if (trayItem.modelData.hasMenu) {
              // Right-clicking a *different* icon while another's menu is
              // already open should switch straight to it, not close --
              // only re-right-clicking the same icon that's already open
              // toggles closed. Checking trayMenuItem too, not just
              // openPopup === "tray", is what tells those two cases apart.
              if (root.openPopup === "tray" && root.trayMenuItem === trayItem.modelData) {
                root.openPopup = "";
              } else {
                root.trayMenuItem = trayItem.modelData;
                root.openPopup = "tray";
              }
            } else {
              trayItem.modelData.secondaryActivate();
            }
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

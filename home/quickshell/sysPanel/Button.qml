import QtQuick
import QtQuick.Layouts
import Quickshell

// ===== BUTTON =====
// Generic icon button: nerd-font glyph, optionally with a live label tacked
// on (Cpu.qml/Battery.qml's "NN%"), + click action.
//
// icon/label are two separate Text items with independently tunable sizes
// -- not one concatenated string at one font size like before. Nerd Fonts'
// own icon glyphs are wildly inconsistent in optical size at the same
// pixel size: bluetooth/wifi/cpu (all nf-md-* Material Design Icons
// codepoints, confirmed via each glyph's actual Unicode value, not just
// eyeballed) render visibly smaller than the battery glyphs (also nf-md-*)
// at 16px, and volume's icon is a Font Awesome codepoint (nf-fa-*), a
// legacy icon set that's well known to render notably smaller than MDI in
// Nerd Fonts generally. `iconSize` below is a best-effort starting point
// for evening that out, not a measured pixel match -- I can't screenshot
// this session's compositor to see the real render (tried grim/spectacle,
// neither works from here), so nudge individual `iconSize`s in Buttons.qml
// if any of these still look off once you actually see it.
Item {
  id: buttonRoot

  property var command: []
  // Only cpu (left: btop, right: plain terminal) uses this, matching
  // waybar's on-click/on-click-right split -- empty means right-click is a
  // no-op, same as every other button that never set it.
  property var rightCommand: []

  property string icon: ""
  property string label: ""
  property int iconSize: 16
  property int labelSize: 14

  implicitWidth: row.implicitWidth + 8
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    x: 4
    spacing: 4

    Text {
      text: buttonRoot.icon
      color: root.fgColor
      font.family: "FiraCode Nerd Font Mono"
      font.pixelSize: buttonRoot.iconSize
    }

    Text {
      visible: buttonRoot.label.length > 0
      text: buttonRoot.label
      color: root.fgColor
      font.family: "FiraCode Nerd Font Mono"
      font.pixelSize: buttonRoot.labelSize
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: (mouse) => {
      if (mouse.button === Qt.RightButton && buttonRoot.rightCommand.length > 0) {
        Quickshell.execDetached(buttonRoot.rightCommand);
      } else {
        Quickshell.execDetached(buttonRoot.command);
      }
    }
  }
}

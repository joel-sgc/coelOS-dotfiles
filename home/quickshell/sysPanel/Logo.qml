import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// ===== LOGO ===== 
IconImage {
  id: root
  
  property var command: ["coel-main-menu"]
  source: Qt.resolvedUrl("../logo.svg")
  mipmap: true
  implicitSize: 24
  
   MouseArea {
    anchors.fill: parent
    onClicked: Quickshell.execDetached(command)
    cursorShape: Qt.PointingHandCursor
  }
}
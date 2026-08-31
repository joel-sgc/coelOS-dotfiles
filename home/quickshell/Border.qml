import Quickshell
import Quickshell.Wayland
import QtQuick

Scope {
  id: root
    
  property int borderWidth: 4
  property color borderColor: "#61afef"
  property int radius: 12
  property bool enabled: true
  property int barHeight: 48

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData

        anchors {
          top: true
          left: true
          right: true
          bottom: true
        }
        margins.top: root.barHeight - 4

        visible: root.enabled
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: null }

        Canvas {
          id: frame
          anchors.fill: parent
        
          property int borderWidth: root.borderWidth
          property color borderColor: root.borderColor
          property int radius: root.radius
        
          onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
        
            // fill the whole area with the border color — square, flush edges
            ctx.fillStyle = borderColor;
            ctx.fillRect(0, 0, width, height);
        
            // cut a rounded rect out of the middle, revealing what's behind
            ctx.globalCompositeOperation = "destination-out";
            ctx.beginPath();
            var x = borderWidth, y = borderWidth;
            var w = width - borderWidth * 2, h = height - borderWidth * 2;
            var r = radius;
        
            ctx.moveTo(x + r, y);
            ctx.arcTo(x + w, y, x + w, y + h, r);
            ctx.arcTo(x + w, y + h, x, y + h, r);
            ctx.arcTo(x, y + h, x, y, r);
            ctx.arcTo(x, y, x + w, y, r);
            ctx.closePath();
            ctx.fill();
          }
        
          // repaint whenever anything relevant changes
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onBorderWidthChanged: requestPaint()
          onBorderColorChanged: requestPaint()
          onRadiusChanged: requestPaint()
        }
      }
    }
  }
}
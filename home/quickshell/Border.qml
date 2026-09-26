import Quickshell
import Quickshell.Wayland
import QtQuick

Scope {
  id: root
    
  // Was a bold 4px accent-blue outline, then a 1px flat #404754 --
  // that flat grey turned out to disappear entirely against wallpapers
  // close to the same color, which defeats the point (marking where the
  // screen edge is versus the desktop behind it). Semi-transparent white
  // lightens whatever's underneath instead of competing with a fixed
  // hue, so it stays visible regardless of wallpaper color.
  property int borderWidth: 12
  property color borderColor: "#14ffffff"
  // A second, thin stroke traced right along the same rounded-rect edge
  // as the cutout, in a brighter shade than the translucent fill --
  // the fill alone is a soft wash that still fades gradually into
  // whatever's behind it rather than reading as a defined line; this
  // gives the frame an actual edge distinguishing it from the desktop.
  property color innerAccentColor: "#22ffffff"
  property real innerAccentWidth: 1.5
  property int radius: 12
  property bool enabled: true
  property int barHeight: 36

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
        margins.top: root.barHeight - borderWidth

        visible: root.enabled
        color: "transparent"

        // One layer below Panel.qml's own Overlay bar, so the bar and its
        // popups always render in front of this screen-edge frame.
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: null }

        Canvas {
          id: frame
          anchors.fill: parent
          z: -1
        
          property int borderWidth: root.borderWidth
          property color borderColor: root.borderColor
          property color innerAccentColor: root.innerAccentColor
          property real innerAccentWidth: root.innerAccentWidth
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

            // trace that same edge with a thin, brighter stroke -- back
            // to normal (additive) compositing first, "destination-out"
            // above would erase instead of draw
            ctx.globalCompositeOperation = "source-over";
            ctx.strokeStyle = innerAccentColor;
            ctx.lineWidth = innerAccentWidth;
            ctx.beginPath();
            ctx.moveTo(x + r, y);
            ctx.arcTo(x + w, y, x + w, y + h, r);
            ctx.arcTo(x + w, y + h, x, y + h, r);
            ctx.arcTo(x, y + h, x, y, r);
            ctx.arcTo(x, y, x + w, y, r);
            ctx.closePath();
            ctx.stroke();
          }

          // repaint whenever anything relevant changes
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onBorderWidthChanged: requestPaint()
          onBorderColorChanged: requestPaint()
          onInnerAccentColorChanged: requestPaint()
          onInnerAccentWidthChanged: requestPaint()
          onRadiusChanged: requestPaint()
        }
      }
    }
  }
}
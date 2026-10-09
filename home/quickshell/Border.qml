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
  property int radius: Globals.eyeCandyOff ? 0 : 16
  property bool enabled: true
  property int barHeight: 36

  // Which screens this file has actually created a window for so far --
  // Panel.qml gates its own per-screen window creation on this (see its
  // own readyScreens property) instead of reacting to Quickshell.screens
  // directly. Both Border and Panel sit on the same WlrLayer.Top, where
  // stacking order within a layer is just "whichever surface the
  // compositor saw created later paints on top" -- reliable at initial
  // startup (both react to the same screens list at once, in declaration
  // order), but NOT reliable for a screen added later (a monitor
  // reconnect), since Border's and Panel's Variants are two independent
  // watchers of the same model with no guaranteed relative order between
  // them. Confirmed live via `hyprctl -j layers`: the primary monitor had
  // the correct [Border, Panel] order, the secondary had it backwards
  // ([Panel, Border], so Border painted over the bar) -- this makes the
  // order structurally guaranteed instead of raced, for every screen,
  // present at startup or added afterward.
  property var readyScreens: []

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData

        Component.onCompleted: {
          if (root.readyScreens.indexOf(modelData) < 0) root.readyScreens = root.readyScreens.concat([modelData]);
        }
        Component.onDestruction: {
          root.readyScreens = root.readyScreens.filter(s => s !== modelData);
        }

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
          property int radius: Globals.eyeCandyOff ? 0 : root.radius

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
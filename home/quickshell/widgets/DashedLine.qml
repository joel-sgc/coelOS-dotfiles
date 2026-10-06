import QtQuick

// 1px dashed horizontal rule (QML has no dashed Rectangle border).
Canvas {
  property color color: Pal.faint
  implicitHeight: 1
  height: 1
  onColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onPaint: {
    const ctx = getContext("2d");
    ctx.reset();
    ctx.strokeStyle = color;
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 3]);
    ctx.beginPath();
    ctx.moveTo(0, 0.5);
    ctx.lineTo(width, 0.5);
    ctx.stroke();
  }
}

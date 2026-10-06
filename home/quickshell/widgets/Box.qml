import QtQuick
import QtQuick.Layouts

// A bordered group with its title cut into the top edge ("legend"), like a
// terminal fieldset. Children go into a ColumnLayout inside the border.
// Extra left-legend content (e.g. the calendar's month arrows) goes in
// leftData; the plain `legend` string is just one Text in that same row.
Item {
  id: box

  property string legend: ""
  property color legendColor: Pal.muted
  property string rightLegend: ""
  property color rightColor: Pal.muted
  property color borderColor: Pal.faint
  property color fillColor: "transparent"
  property int padTop: 14
  property int padSide: 8
  property int padBottom: 8
  property alias spacing: inner.spacing
  default property alias content: inner.data
  property alias leftData: leftRow.data
  property alias rightData: rightRow.data

  implicitHeight: inner.implicitHeight + padTop + padBottom

  Rectangle {
    anchors.fill: parent
    radius: 2
    color: box.fillColor
    border.width: 1
    border.color: box.borderColor
  }

  ColumnLayout {
    id: inner
    anchors {
      left: parent.left; right: parent.right; top: parent.top
      leftMargin: box.padSide; rightMargin: box.padSide; topMargin: box.padTop
    }
    spacing: 0
  }

  Rectangle {
    visible: leftRow.implicitWidth > 0
    x: 8
    y: -height / 2
    width: leftRow.implicitWidth + 12
    height: leftRow.implicitHeight
    color: Pal.card
    Row {
      id: leftRow
      anchors.centerIn: parent
      spacing: 6
      Mono { visible: box.legend !== ""; text: box.legend; color: box.legendColor }
    }
  }

  Rectangle {
    visible: rightRow.implicitWidth > 0
    anchors.right: parent.right
    anchors.rightMargin: 8
    y: -height / 2
    width: rightRow.implicitWidth + 12
    height: rightRow.implicitHeight
    color: Pal.card
    Row {
      id: rightRow
      anchors.centerIn: parent
      spacing: 6
      Mono { visible: box.rightLegend !== ""; text: box.rightLegend; color: box.rightColor }
    }
  }
}

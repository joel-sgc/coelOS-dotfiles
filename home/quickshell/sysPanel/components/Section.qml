import QtQuick

// ===== SECTION =====
// The bordered-box-with-a-floating-label pattern every dropdown in the
// design mock uses repeatedly (battery/power-mode/utilities in
// PowerDropdown.qml; the same shape reappears for bluetooth/network/audio/
// system in later phases) -- a 1px border with a label sitting on top of
// its top edge, done by painting the label over the line with the popup's
// own background color rather than any real border-break trick.
//
// Sizing is all non-circular by construction: `inner`'s height comes from
// its own children's natural implicitHeight (a Column laid out top-down),
// `border`'s height follows `inner`, and this Item's implicitHeight
// follows `border` -- nothing here is bound back from a parent that is
// itself waiting on this size, which is what actually matters (an anchors-
// fill child measuring against a parent whose own size comes from that
// same child is the loop to avoid).
Item {
  id: sectionRoot

  property string label: ""
  property color labelColor: "#5c6370"
  // Optional floating control in the top-right corner of the border (the
  // mock uses this for the battery box's AC status and the power-mode
  // box's "power-profiles-daemon" caption) -- a full Item so callers can
  // put a button or a plain Text there, not just a string.
  property alias rightContent: rightSlotHolder.data

  property color borderColor: "#404754"
  property color bgColor: "#282c34"

  property int paddingTop: 12
  property int paddingBottom: 8
  property int paddingSide: 10
  property int spacing: 6

  default property alias content: inner.data

  implicitWidth: parent ? parent.width : border.implicitWidth
  implicitHeight: border.height + 9

  Rectangle {
    id: border
    anchors.top: parent.top
    anchors.topMargin: 9
    anchors.left: parent.left
    anchors.right: parent.right
    height: inner.implicitHeight + sectionRoot.paddingTop + sectionRoot.paddingBottom
    color: "transparent"
    border.width: 1
    border.color: sectionRoot.borderColor
    radius: 2
  }

  Column {
    id: inner
    anchors.top: border.top
    anchors.left: border.left
    anchors.right: border.right
    anchors.topMargin: sectionRoot.paddingTop
    anchors.leftMargin: sectionRoot.paddingSide
    anchors.rightMargin: sectionRoot.paddingSide
    spacing: sectionRoot.spacing
  }

  Text {
    id: labelText
    visible: sectionRoot.label.length > 0
    x: 8
    y: border.y - height / 2
    leftPadding: 6
    rightPadding: 6
    color: sectionRoot.labelColor
    text: sectionRoot.label
    font.family: "JetBrains Mono"
    font.pixelSize: 13

    Rectangle {
      z: -1
      anchors.fill: parent
      color: sectionRoot.bgColor
    }
  }

  Item {
    id: rightSlot
    // Sized from rightSlotHolder's children, not its own -- rightSlot's
    // background rectangle below anchors to rightSlot itself, and if
    // rightSlot's own size came from childrenRect (which would then
    // include that rectangle) the two would feed each other: confirmed
    // live as a real "Binding loop detected for property height/width"
    // warning the first time this was tried the direct way. Routing
    // content through a separate inner Item breaks that cycle -- the
    // background can depend on rightSlot's size, rightSlot's size just
    // can't also depend on the background.
    width: rightSlotHolder.childrenRect.width
    height: rightSlotHolder.childrenRect.height
    x: parent.width - width - 8 - 6
    y: border.y - height / 2

    // Same border-masking background labelText gets above -- this was
    // missing entirely before, which is why right-side content (AC
    // status, "power-profiles-daemon") looked like it was sitting on top
    // of the border line instead of breaking it the same clean way the
    // left label does.
    Rectangle {
      z: -1
      anchors.fill: parent
      anchors.margins: -6
      color: sectionRoot.bgColor
    }

    Item {
      id: rightSlotHolder
      anchors.fill: parent
    }
  }
}

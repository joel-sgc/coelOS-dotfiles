import QtQuick
import QtQuick.Layouts

import "../Phosphor.js" as Phosphor

// One notification row inside NotificationsDropdown.qml's list view.
// `nRoot` is passed in explicitly (rather than relying on the
// unqualified-`root` id-scope chain every bar button/dropdown normally
// uses) because this component is instantiated from inside a Repeater
// nested two levels deep (group Column -> item Repeater), where plain `id`
// lookups up the visual parent chain get unreliable. Deliberately not
// named `dropdownRoot` (which NotificationsDropdown.qml's own root `id`
// actually is) -- `dropdownRoot: dropdownRoot` in the delegate would have
// self-shadowed to this component's own (then-null) property instead of
// reaching the outer id, which is exactly the bug this naming avoids.
//
// The conditional actions/reply rows below are plain `Row`, not
// `RowLayout` -- an earlier version used RowLayout here and hit two real
// bugs live: font.pixelSize rejected fractional values (QtQuick.Layouts
// didn't surface this any differently, but it's the same strict-int rule),
// and toggling `visible` on a RowLayout didn't reliably propagate its new
// implicit size up through this row's own `implicitHeight` binding,
// producing rows that visually overlapped the next one instead of pushing
// it down. A plain positioner recomputes synchronously on every child
// property change with no such staleness.
Item {
  id: rowRoot

  property var n: null
  property var nRoot: null
  property bool selected: false

  readonly property bool isCritical: n.urgency === "critical"
  readonly property bool isMuted: nRoot.isMuted(n.app)
  readonly property bool isReplying: nRoot.replyingId === n.id
  // Grabs focus only at the moment THIS row actually becomes the one
  // replying -- not at creation time (see replyField's own comment for why
  // Component.onCompleted was wrong here). A plain Item's own `visible`
  // doesn't track an ancestor's visibility as a bindable change signal, so
  // this has to key off `isReplying` directly, not replyField.visible.
  onIsReplyingChanged: if (isReplying) replyField.forceActiveFocus()
  // Whether the body is actually clamped right now -- real notification
  // bodies vary wildly in length, so this is read off bodyText's own
  // `truncated` (set correctly by Qt's text layout) rather than guessed
  // from a character count. `|| n.expanded` keeps [less] showing once
  // expanded, since `truncated` itself goes false the moment elision is
  // turned off.
  readonly property bool canExpand: n.expanded || bodyText.truncated

  implicitHeight: col.implicitHeight + 16

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: rowRoot.selected ? "#2f343e" : (mouseArea.containsMouse ? "#2f343e" : "transparent")
    border.width: 1
    // Critical always wins (red), regardless of selection; otherwise
    // selected gets the accent blue; every other card still gets a
    // visible default border, not "transparent" -- the mock borders
    // every card, selection/critical just override its color.
    border.color: rowRoot.isCritical ? nRoot.colors[1] : (rowRoot.selected ? nRoot.colors[0] : nRoot.hoverColor)
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    onClicked: nRoot.selectId(rowRoot.n.id)
    onDoubleClicked: nRoot.openApp(rowRoot.n)
  }

  // Manual x-positioning (icon at a fixed x, `col` filling the rest), not
  // a RowLayout wrapping both -- a RowLayout here was the real cause of a
  // live-confirmed bug: `col`'s height legitimately changes when the
  // actions row's `visible` flips (selecting a different notification),
  // but that change didn't reliably propagate back up through the
  // RowLayout's own implicitHeight in time, leaving `rowRoot.implicitHeight`
  // stale and the next row overlapping this one. Plain positioners
  // (Column/Row) recompute synchronously with no such lag; this sidesteps
  // the whole class of bug by keeping the dynamic-height chain off
  // QtQuick.Layouts entirely, same reasoning as the actions/reply rows
  // below already being plain Row instead of RowLayout.
  // A thumbnail of the notification's own real image when it has one,
  // instead of always showing a generic per-app placeholder glyph -- the
  // glyph doesn't actually identify anything useful for an app like Satty
  // (a screenshot tool), where the real image *is* the whole point of the
  // notification. Falls back to the glyph while the image is loading or
  // if there isn't one.
  Item {
    id: iconSlot
    x: 10
    y: 6
    width: 20
    height: 20

    Image {
      id: iconImage
      anchors.fill: parent
      // The real extracted screenshot (previewImage) when there is one --
      // otherwise whatever `image` resolved to, which for most real
      // senders is just their app icon (see this file's own notes above).
      source: rowRoot.n.previewImage.length > 0 ? rowRoot.n.previewImage : (rowRoot.n.hasImage ? rowRoot.n.image : "")
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: status === Image.Ready
    }
    Text {
      visible: iconImage.status !== Image.Ready
      anchors.centerIn: parent
      text: Phosphor.icon(rowRoot.n.icon)
      font.family: "Phosphor"
      font.pixelSize: 17
      color: rowRoot.isCritical ? nRoot.colors[1] : nRoot.colors[0]
    }
  }

  Column {
      id: col
      x: iconSlot.x + iconSlot.width + 10
      y: 8
      width: parent.width - x - 10
      spacing: 3

      RowLayout {
        width: parent.width
        spacing: 6
        Text { text: rowRoot.n.app; color: nRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
        Text { text: "·"; color: nRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
        Text { text: rowRoot.n.time; color: nRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
        Text { visible: rowRoot.isCritical; text: "critical"; color: nRoot.colors[1]; font.family: "JetBrains Mono"; font.pixelSize: 12 }
        RowLayout {
          visible: rowRoot.isMuted
          spacing: 3
          Text { text: Phosphor.icon("speaker-simple-slash"); font.family: "Phosphor"; font.pixelSize: 12; color: nRoot.mutedColor }
          Text { text: "muted"; color: nRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
        }
        Item { Layout.fillWidth: true }
        Rectangle {
          visible: rowRoot.n.fresh
          width: 6; height: 6; radius: 3
          color: nRoot.colors[0]
        }
        Text {
          text: "[×]"
          color: nRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.dismiss(rowRoot.n.id) }
        }
      }

      Text { width: parent.width; text: rowRoot.n.summary; color: nRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
      Text {
        id: bodyText
        width: parent.width
        text: rowRoot.n.body
        color: nRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        // 0, not `undefined` -- maximumLineCount is a plain int property;
        // `undefined` silently fails the same way a fractional
        // font.pixelSize did elsewhere in this file (both confirmed live).
        // 0 is Qt's own "no limit" value.
        maximumLineCount: rowRoot.n.expanded ? 0 : 2
        elide: rowRoot.n.expanded ? Text.ElideNone : Text.ElideRight
      }

      // A real large preview, but only when previewImage actually found a
      // real screenshot path in Satty's own body text (dropdownRoot's
      // extractPreviewImage()) -- not driven by `image`/`hasImage` anymore,
      // since that's just the sending app's icon for most real senders
      // (confirmed live against real DB rows: Satty/KDE Connect's own
      // `image` resolved to their .svg/icon data, not real content). This
      // is deliberately Satty-specific for now, not a generic "any app
      // with an image hint gets a big box" rule.
      Rectangle {
        visible: rowRoot.n.previewImage.length > 0
        width: parent.width
        height: 120
        radius: 4
        color: "#21252b"
        border.width: 1
        border.color: nRoot.hoverColor
        clip: true

        Image {
          id: previewImg
          anchors.fill: parent
          source: rowRoot.n.previewImage
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          visible: status === Image.Ready
        }
        Text {
          visible: previewImg.status !== Image.Ready
          anchors.centerIn: parent
          text: Phosphor.icon("image")
          font.family: "Phosphor"
          font.pixelSize: 18
          color: nRoot.mutedColor
        }
      }

      Row {
        visible: rowRoot.selected && !rowRoot.isReplying
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: 14

        Text {
          text: "[show app]"
          color: nRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.openApp(rowRoot.n) }
        }
        Text {
          visible: !rowRoot.n.read
          text: "[mark read]"
          color: nRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.markRead(rowRoot.n.id) }
        }
        Repeater {
          model: rowRoot.n.actions
          delegate: Text {
            required property var modelData
            text: "[" + modelData.label + "]"
            color: nRoot.colors[0]
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.runAction(rowRoot.n, parent.modelData) }
          }
        }
        Text {
          visible: rowRoot.n.canReply
          text: "[reply]"
          color: nRoot.colors[3]
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.startReply(rowRoot.n) }
        }
        Text {
          visible: rowRoot.canExpand
          text: rowRoot.n.expanded ? "[less]" : "[more]"
          color: nRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.toggleExpand(rowRoot.n.id) }
        }
        Text {
          text: "[copy]"
          color: nRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.copyNotif(rowRoot.n) }
        }
        Text {
          text: rowRoot.isMuted ? "[unmute]" : "[mute]"
          color: nRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.toggleMute(rowRoot.n.app) }
        }
      }

      // An Item, not a Row -- every child here needs vertical centering,
      // and anchoring a Row's own direct children conflicts with the
      // Row's x-positioning of those same children (see the dnd toggle's
      // comment in NotificationsDropdown.qml for the full explanation of
      // this bug class). Explicit x math instead. Bordered like the mock's
      // own reply affordance (missing from an earlier pass entirely --
      // no border, no placeholder, confirmed live against the mock's
      // screenshot).
      Rectangle {
        id: replyRow
        visible: rowRoot.isReplying
        width: parent.width
        height: visible ? 28 : 0
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: nRoot.colors[0]
        clip: true

        Text {
          id: replyIcon
          x: 10
          anchors.verticalCenter: parent.verticalCenter
          text: Phosphor.icon("arrow-bend-up-left")
          font.family: "Phosphor"
          color: nRoot.colors[0]
        }
        TextInput {
          id: replyField
          x: replyIcon.x + replyIcon.implicitWidth + 8
          width: parent.width - x - 92
          anchors.verticalCenter: parent.verticalCenter
          text: nRoot.replyText
          color: nRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          selectByMouse: true
          onTextEdited: nRoot.replyText = text
          onAccepted: nRoot.sendReply()
          // No Component.onCompleted here -- see rowRoot's own
          // onIsReplyingChanged handler above for why (this TextInput is a
          // static child of every row regardless of whether it's the one
          // replying, so onCompleted would fire once per row at
          // dropdown-open time for all of them, and whichever row was
          // created last would silently steal keyboard focus from
          // dropdownRoot every single time -- confirmed live as the real
          // cause behind "the keybinds don't work": mouse-driven actions
          // like clicking [reply] were never affected since they don't
          // depend on dropdownRoot's Keys.onPressed, but every keyboard
          // shortcut, z/v/j/k included, silently went nowhere).

          Text {
            visible: replyField.text.length === 0
            anchors.verticalCenter: parent.verticalCenter
            text: "reply to " + rowRoot.n.summary
            color: nRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: "[send ⏎]"
          color: nRoot.colors[0]
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.sendReply() }
        }
      }
  }
}

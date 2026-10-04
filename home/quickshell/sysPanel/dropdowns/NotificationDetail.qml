import QtQuick
import QtQuick.Layouts

import "../Phosphor.js" as Phosphor

// Right-hand detail pane for NotificationsDropdown.qml's split view --
// same data/actions as NotificationRow.qml, just laid out bigger, plus the
// raw metadata rows (`rows`) the list view doesn't show. `nRoot`, not
// `dropdownRoot` -- see NotificationRow.qml's header comment for why.
Item {
  id: detailRoot

  property var n: null
  property var rows: []
  property var nRoot: null

  readonly property bool isCritical: n !== null && n.urgency === "critical"
  readonly property bool isMuted: n !== null && nRoot.isMuted(n.app)
  readonly property bool isReplying: n !== null && nRoot.replyingId === n.id
  // Grabs focus only when replying actually starts -- this pane's reply
  // TextInput is a static child created the moment the split-view
  // RowLayout exists (which happens on dropdown open regardless of
  // viewMode, not lazily when split is selected), so a
  // Component.onCompleted here fired immediately on every open and stole
  // focus even in list view -- see NotificationRow.qml's own version of
  // this same bug/fix for the full explanation.
  onIsReplyingChanged: if (isReplying) replyField.forceActiveFocus()

  // A real Flickable, not a fixed-height ColumnLayout -- the split view's
  // container is a fixed 440px, and a long body plus the real image
  // preview (previewImage) together could genuinely exceed that. Neither
  // ColumnLayout nor its children clip by default, so overflowing content
  // just rendered past this pane's own bounds -- and since Popup.qml
  // auto-sizes the whole frame off `childrenRect` (which measures actual
  // rendered geometry, not nominal layout bounds), that overflow was
  // inflating the *entire dropdown's* height, not just spilling messily
  // within this one pane (confirmed live: the whole card grew taller and
  // the footer got pushed out of view). `clip: true` here contains it;
  // Flickable makes the rest actually reachable by scrolling instead of
  // just invisible.
  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: contentCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: contentCol
      width: parent.width
      spacing: 12
      visible: detailRoot.n !== null

      RowLayout {
      Layout.fillWidth: true
      spacing: 12

      Rectangle {
        width: 38; height: 38; radius: 8
        color: "#21252b"
        border.width: 1
        border.color: nRoot.hoverColor
        clip: true

        // Real image thumbnail when there is one, instead of always a
        // generic per-app glyph -- same reasoning as NotificationRow.qml's
        // own icon slot (the glyph doesn't identify anything useful for
        // e.g. Satty, where the image itself is the real content).
        Image {
          id: headerImage
          anchors.fill: parent
          // The real extracted screenshot (previewImage) when there is
          // one -- otherwise whatever `image` resolved to, which for most
          // real senders is just their app icon (see this file's own
          // notes above).
          source: detailRoot.n && detailRoot.n.previewImage.length > 0 ? detailRoot.n.previewImage : ((detailRoot.n && detailRoot.n.hasImage) ? detailRoot.n.image : "")
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: status === Image.Ready
        }
        Text {
          visible: headerImage.status !== Image.Ready
          anchors.centerIn: parent
          text: detailRoot.n ? Phosphor.icon(detailRoot.n.icon) : ""
          font.family: "Phosphor"
          font.pixelSize: 20
          color: detailRoot.isCritical ? nRoot.colors[1] : nRoot.colors[0]
        }
      }
      Column {
        Layout.fillWidth: true
        Text { text: detailRoot.n ? detailRoot.n.summary : ""; color: nRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 14; wrapMode: Text.WordWrap; width: parent.width }
        Text { text: detailRoot.n ? (detailRoot.n.app + " · " + detailRoot.n.time) : ""; color: nRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
      }
      Text {
        text: "[×]"
        color: nRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
        Layout.alignment: Qt.AlignTop
        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: if (detailRoot.n) nRoot.dismiss(detailRoot.n.id) }
      }
    }

    Text {
      Layout.fillWidth: true
      text: detailRoot.n ? detailRoot.n.body : ""
      color: nRoot.mutedColor
      font.family: "JetBrains Mono"
      font.pixelSize: 13
      wrapMode: Text.WordWrap
    }

    // A real large preview, but only when previewImage actually found a
    // real screenshot path in Satty's own body text -- see
    // NotificationRow.qml's own version of this same block for the full
    // explanation (not driven by `hasImage`/`image` anymore, since that's
    // just the sending app's icon for most real senders).
    Rectangle {
      visible: detailRoot.n && detailRoot.n.previewImage.length > 0
      Layout.fillWidth: true
      height: 160
      radius: 4
      color: "#21252b"
      border.width: 1
      border.color: nRoot.hoverColor
      clip: true

      Image {
        id: previewImg
        anchors.fill: parent
        source: detailRoot.n ? detailRoot.n.previewImage : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: status === Image.Ready
      }
      Text {
        visible: previewImg.status !== Image.Ready
        anchors.centerIn: parent
        text: Phosphor.icon("image")
        font.family: "Phosphor"
        font.pixelSize: 24
        color: nRoot.mutedColor
      }
    }

    Row {
      visible: detailRoot.n && !detailRoot.isReplying
      Layout.fillWidth: true
      height: visible ? implicitHeight : 0
      spacing: 14

      Text {
        text: "[show app]"
        color: nRoot.fgColor
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: if (detailRoot.n) nRoot.openApp(detailRoot.n) }
      }
      Text {
        visible: detailRoot.n && !detailRoot.n.read
        text: "[mark read]"
        color: nRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: if (detailRoot.n) nRoot.markRead(detailRoot.n.id) }
      }
      Repeater {
        model: detailRoot.n ? detailRoot.n.actions : []
        delegate: Text {
          required property var modelData
          text: "[" + modelData.label + "]"
          color: nRoot.colors[0]
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: nRoot.runAction(detailRoot.n, parent.modelData) }
        }
      }
      Text {
        visible: detailRoot.n && detailRoot.n.canReply
        text: "[reply]"
        color: nRoot.colors[3]
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: if (detailRoot.n) nRoot.startReply(detailRoot.n) }
      }
      Text {
        text: "[copy]"
        color: nRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: if (detailRoot.n) nRoot.copyNotif(detailRoot.n) }
      }
      Text {
        text: detailRoot.isMuted ? "[unmute]" : "[mute]"
        color: nRoot.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 12
        MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: if (detailRoot.n) nRoot.toggleMute(detailRoot.n.app) }
      }
    }

    // An Item, not a Row -- see NotificationRow.qml's own reply-row
    // comment for why anchoring a Row's direct children (every child here
    // needs vertical centering) is unsafe. Bordered + placeholder, same
    // fix as NotificationRow.qml's own reply row.
    Rectangle {
      visible: detailRoot.isReplying
      Layout.fillWidth: true
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

        Text {
          visible: replyField.text.length === 0
          anchors.verticalCenter: parent.verticalCenter
          text: detailRoot.n ? ("reply to " + detailRoot.n.summary) : ""
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

    // No fillHeight spacer pinning this to the bottom anymore -- that only
    // made sense against a fixed-height parent; inside a Flickable there's
    // no fixed height to pin against, so metadata just follows normally
    // with regular spacing instead.

    // Metadata rows (app/urgency/received/id) -- a Column of Rows, one per
    // entry, NOT a `Grid { columns: 2 }` with a single two-Text delegate
    // per entry: Grid treats each *delegate* as one cell among its
    // `columns`, so pairing key+value inside one delegate while columns:2
    // silently laid out two whole *entries* side by side instead of one
    // entry's key/value pair -- a real bug an earlier version of this file
    // had, caught from a live screenshot showing only 2 of 4 rows with the
    // rest pushed off to the side.
    Column {
      Layout.fillWidth: true
      spacing: 2
      Repeater {
        model: detailRoot.rows
        delegate: Row {
          required property var modelData
          width: parent.width
          spacing: 10
          Text { text: parent.modelData.k; color: nRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12; width: 70 }
          Text { text: parent.modelData.v; color: parent.modelData.c; font.family: "JetBrains Mono"; font.pixelSize: 12; width: parent.width - 80; elide: Text.ElideRight }
        }
      }
    }
    }
  }
}

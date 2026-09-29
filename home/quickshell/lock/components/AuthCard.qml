import QtQuick
import QtQuick.Layouts
import "../../sysPanel/Phosphor.js" as Phosphor

// ===== AUTH CARD =====
// Bottom-right 332px card in the "1a Corner" mockup: user-switcher row
// (login mode only), avatar/username/locked-line, password pill, status
// line + fingerprint button, then the power-button row + CoelOS wordmark.
//
// Pure props-down/signals-up presentational component -- Lock.qml owns
// every piece of state here (see its own comments for why: this pass fakes
// the whole auth/power state machine locally, exactly like the mockup's
// own <script data-dc-script> Component class, with no real PAM/systemd
// backend wired in yet).
Item {
  id: root

  property color fgColor: "#abb2bf"
  property color brightColor: "#d7dae0"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property color inputBg: "#1e2127"
  property color rowBg: "#2f343e"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]

  property string mode: "lock" // "lock" | "login"
  property var users: [] // [{name, init}]
  property int selectedUser: 0
  property var sessions: [] // [string]
  property int selectedSession: 0
  property string lockedAtText: ""

  property string pw: ""
  property bool showPw: false
  property string authState: "idle" // idle | checking | ok
  property var statusLine: ({ icon: "", text: "", color: "#5c6370" })
  property bool capsOn: false
  property string armedPower: ""
  property var powerActions: [] // [{id, icon, label, command}]
  // Real fingerprint enrollment status (AuthBackend.fingerprintEnrolled) --
  // purely a passive "is this even available" indicator now, not a
  // button: fingerprint listening runs continuously in the background
  // per explicit request, matching real hyprlock's own always-on native
  // backend, so there's nothing left here to click to "start" it.
  property bool fpOn: true
  // Bumped by Lock.qml on every wrong-password/failed-fingerprint attempt
  // to retrigger the shake below -- restart() works regardless of value,
  // unlike the mockup's odd/even keyframe-name trick which only existed to
  // force a CSS re-trigger.
  property int shakeSeq: 0

  signal pwEdited(string text)
  signal submitRequested()
  signal toggleShowRequested()
  signal pickUserRequested(int index)
  signal sessionStepRequested(int delta)
  signal switchModeRequested(string mode)
  signal powerRequested(var action)
  // F9 while the password field has focus -- QA-only stand-in for real
  // CapsLock detection, which is out of scope this pass (no PAM wiring
  // yet to make it meaningful, see the lock-screen plan).
  signal debugCapsToggleRequested()

  readonly property bool isLogin: mode === "login"
  readonly property bool isBad: statusLine && statusLine.color === root.colors[1]
  readonly property color pillBorderColor: authState === "ok" ? colors[3] : isBad ? colors[1] : capsOn ? colors[2] : hoverColor
  readonly property string lockIconName: authState === "ok" ? "lock-simple-open" : "lock-simple"
  readonly property color lockIconColor: authState === "ok" ? colors[3] : mutedColor
  // Steady, not state-driven -- there's no "scanning" state to react to
  // any more (see fpOn's comment above), just available-or-not.
  readonly property color fpIconColor: authState === "ok" ? colors[3] : colors[0]

  implicitWidth: 332
  implicitHeight: col.implicitHeight

  Column {
    id: col
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: 332
    spacing: 14

    // ----- user switcher (login mode only) -----
    Row {
      visible: root.isLogin
      spacing: 10
      Repeater {
        model: root.users
        delegate: Rectangle {
          id: userChip
          required property var modelData
          required property int index
          readonly property bool selected: index === root.selectedUser

          implicitWidth: chipRow.implicitWidth + 20
          implicitHeight: 34
          radius: 8
          color: "#23272e"
          border.width: 1
          border.color: selected ? root.colors[0] : root.rowBg

          RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
              implicitWidth: 22
              implicitHeight: 22
              radius: 11
              color: root.rowBg
              Text {
                anchors.centerIn: parent
                text: userChip.modelData.init
                color: root.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 11
              }
            }
            Text {
              text: userChip.modelData.name
              color: userChip.selected ? root.brightColor : root.fgColor
              font.family: "JetBrains Mono"
              font.pixelSize: 12
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pickUserRequested(userChip.index)
          }
        }
      }
    }

    // ----- avatar / username / locked-or-session row -----
    RowLayout {
      width: col.width
      spacing: 12

      Rectangle {
        implicitWidth: 40
        implicitHeight: 40
        radius: 20
        color: root.rowBg
        border.width: 1
        border.color: root.hoverColor
        Text {
          anchors.centerIn: parent
          text: root.users.length > 0 ? root.users[root.selectedUser].init : ""
          color: root.colors[0]
          font.family: "JetBrains Mono"
          font.pixelSize: 16
        }
      }

      // Plain Item + Column, not ColumnLayout -- Layout.alignment on this
      // section's children was never reliably taking effect (confirmed by
      // direct screenshot measurement more than once, still visibly not
      // flush-left in practice regardless). A Column is a positioner: it
      // has no cross-axis "alignment" concept to get wrong at all, every
      // child sits at exactly x:0 of the Column, always. This removes the
      // whole class of Layout-alignment ambiguity instead of continuing to
      // chase it.
      Item {
        Layout.fillWidth: true
        implicitHeight: userCol.implicitHeight

        Column {
          id: userCol
          x: 0
          width: parent.width
          spacing: 2

          Text {
            text: root.users.length > 0 ? root.users[root.selectedUser].name : ""
            color: root.brightColor
            font.family: "JetBrains Mono"
            font.pixelSize: 15
          }
          Text {
            visible: !root.isLogin
            text: "locked · " + root.lockedAtText
            color: root.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }
          Row {
            visible: root.isLogin
            spacing: 4
          Text {
            text: Phosphor.icon("caret-left")
            color: root.mutedColor
            font.family: "Phosphor"
            font.pixelSize: 11
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.sessionStepRequested(-1) }
          }
          Text {
            // 64px was a placeholder that never got sized against real
            // session names -- confirmed live that names like "Hyprland
            // (uwsm-managed)" need ~165px at this font size and were
            // overflowing into the right-caret arrow next to them. The
            // row actually has ~280px available (RowLayout width 332
            // minus the 40px avatar and spacing), so 220px leaves
            // headroom plus an elide fallback for anything longer still.
            text: root.sessions.length > 0 ? root.sessions[root.selectedSession] : ""
            color: root.fgColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            width: 220
            elide: Text.ElideRight
            clip: true
            horizontalAlignment: Text.AlignLeft
          }
          Text {
            text: Phosphor.icon("caret-right")
            color: root.mutedColor
            font.family: "Phosphor"
            font.pixelSize: 11
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.sessionStepRequested(1) }
          }
          }
        }
      }

      Rectangle {
        visible: !root.isLogin
        implicitWidth: switchRow.implicitWidth + 12
        implicitHeight: 24
        radius: 6
        color: switchMouse.containsMouse ? root.rowBg : "transparent"
        RowLayout {
          id: switchRow
          anchors.centerIn: parent
          spacing: 5
          Text {
            text: Phosphor.icon("users")
            color: root.mutedColor
            font.family: "Phosphor"
            font.pixelSize: 13
          }
          Text {
            text: "switch"
            color: root.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
          }
        }
        MouseArea {
          id: switchMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.switchModeRequested("login")
        }
      }
    }

    // ----- password pill -----
    Item {
      id: shakeWrap
      width: col.width
      height: 44

      Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.inputBg
        border.width: 1
        border.color: root.pillBorderColor
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 6
        spacing: 8

        Text {
          text: Phosphor.icon(root.lockIconName)
          color: root.lockIconColor
          font.family: "Phosphor"
          font.pixelSize: 15
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          TextInput {
            id: pwInput
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            text: root.pw
            echoMode: root.showPw ? TextInput.Normal : TextInput.Password
            color: root.brightColor
            font.family: "JetBrains Mono"
            font.pixelSize: 14
            font.letterSpacing: 1
            selectByMouse: true
            onTextEdited: root.pwEdited(text)
            Keys.onPressed: (event) => {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true;
                root.submitRequested();
              } else if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                root.pwEdited("");
              } else if (event.key === Qt.Key_F9) {
                event.accepted = true;
                root.debugCapsToggleRequested();
              }
            }
          }
          Text {
            visible: pwInput.text.length === 0 && !pwInput.activeFocus
            anchors.verticalCenter: parent.verticalCenter
            text: "password"
            color: root.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 14
          }
        }

        Text {
          text: root.showPw ? Phosphor.icon("eye-slash") : Phosphor.icon("eye")
          color: eyeMouse.containsMouse ? root.fgColor : root.mutedColor
          font.family: "Phosphor"
          font.pixelSize: 15
          MouseArea {
            id: eyeMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleShowRequested()
          }
        }

        Rectangle {
          implicitWidth: 32
          implicitHeight: 32
          radius: 6
          color: submitMouse.containsMouse ? root.rowBg : "transparent"
          border.width: 1
          border.color: submitMouse.containsMouse ? root.colors[0] : root.hoverColor
          Text {
            anchors.centerIn: parent
            text: Phosphor.icon("arrow-right")
            color: root.colors[0]
            font.family: "Phosphor"
            font.pixelSize: 15
          }
          MouseArea {
            id: submitMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.submitRequested()
          }
        }
      }

      SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shakeWrap; property: "x"; to: -9; duration: 90 }
        NumberAnimation { target: shakeWrap; property: "x"; to: 8; duration: 90 }
        NumberAnimation { target: shakeWrap; property: "x"; to: -5; duration: 90 }
        NumberAnimation { target: shakeWrap; property: "x"; to: 3; duration: 90 }
        NumberAnimation { target: shakeWrap; property: "x"; to: 0; duration: 60 }
      }
      Connections {
        target: root
        function onShakeSeqChanged() { shakeAnim.restart(); }
      }
    }

    // ----- status line + fingerprint -----
    RowLayout {
      width: col.width
      spacing: 10

      RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
          visible: root.statusLine.icon.length > 0
          // `visible: false` doesn't stop this binding from still
          // evaluating -- Phosphor.icon("") warned on every idle-state
          // frame until this guarded the call itself, not just the icon.
          text: root.statusLine.icon.length > 0 ? Phosphor.icon(root.statusLine.icon) : ""
          color: root.statusLine.color
          font.family: "Phosphor"
          font.pixelSize: 13
        }
        Text {
          text: root.statusLine.text
          color: root.statusLine.color
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      // Passive status indicator, not a button -- see fpOn's comment
      // above. No MouseArea/click handler: fingerprint listening is
      // always running in the background regardless of anything here.
      Text {
        visible: root.fpOn
        text: Phosphor.icon("fingerprint")
        color: root.fpIconColor
        font.family: "Phosphor"
        font.pixelSize: 22
      }
    }

    // ----- power buttons + wordmark -----
    RowLayout {
      width: col.width
      spacing: 4

      Repeater {
        model: root.powerActions
        delegate: Rectangle {
          id: pwrBtn
          required property var modelData
          readonly property bool armed: root.armedPower === modelData.id

          implicitWidth: pwrRow.implicitWidth + 12
          implicitHeight: 26
          radius: 6
          color: pwrMouse.containsMouse ? root.rowBg : "transparent"

          RowLayout {
            id: pwrRow
            anchors.centerIn: parent
            spacing: 6
            Text {
              text: Phosphor.icon(pwrBtn.modelData.icon)
              color: pwrBtn.armed ? root.colors[1] : root.mutedColor
              font.family: "Phosphor"
              font.pixelSize: 14
            }
            Text {
              visible: pwrBtn.armed
              text: pwrBtn.modelData.label + "?"
              color: root.colors[1]
              font.family: "JetBrains Mono"
              font.pixelSize: 12
            }
          }

          MouseArea {
            id: pwrMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.powerRequested(pwrBtn.modelData)
          }
        }
      }

      Item { Layout.fillWidth: true }

      // The mock CSS-masks this to a flat accent-blue silhouette
      // (mask:url(...) background:accent). Plain, un-recolored PNG here --
      // QtQuick core has no built-in mask/colorize primitive, and pulling
      // in QtQuick.Effects' MultiEffect for one static logo felt like a
      // new dependency disproportionate to this pass. Revisit if the
      // plain rendering doesn't read well once screenshot-checked.
      Image {
        source: Qt.resolvedUrl("../../assets/coelos-wordmark.png")
        sourceSize.height: 28
        fillMode: Image.PreserveAspectFit
        Layout.preferredWidth: 128
        Layout.preferredHeight: 28
        opacity: 0.85
      }
    }
  }
}

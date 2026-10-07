import QtQuick
import QtQuick.Layouts
import "../widgets"
import "../sysPanel/Phosphor.js" as Phosphor

// ===== POLKIT AUTHENTICATION DIALOG =====
// Ported from example/Polkit Agent.dc.html. Pure view: Polkit.qml owns the
// agent and feeds this the request + state; this reports what the user did
// (submitted / cancelled / cycleIdentity).
Item {
  id: root

  // request
  property string message: ""
  property string actionId: ""
  property string iconName: ""
  property string via: "polkit"
  property string glyph: "lock-simple"
  property color tone: Pal.blue
  // [{label, note}]
  property var identities: []
  property int identityIndex: 0
  // conversation
  property string phase: "input"        // input | verifying | success
  property bool responseRequired: false
  property string prompt: ""
  property bool echo: false
  property string errorText: ""         // "sorry, try again."
  // fingerprint: none | listening | nomatch | match
  property string fpState: "none"
  property bool fpSeen: false
  property string fpMeta: "fprintd"
  property real shakeX: 0

  signal submitted(string password)
  signal cancelled()
  signal cycleIdentity()

  readonly property bool busy: phase !== "input"
  readonly property bool pwVisible: responseRequired || !fpSeen
  readonly property bool fpBig: fpSeen && !responseRequired
  readonly property bool fpCompact: fpSeen && responseRequired
  readonly property string userName: identities.length ? identities[identityIndex].label : ""
  readonly property bool canSubmit: pwVisible && responseRequired && pwInput.text !== "" && phase === "input"
  property bool revealed: false
  property bool details: false
  property var detailRows: []
  property int spinTick: 0
  readonly property string spin: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[spinTick % 10]

  // the password field when it's usable, else the dialog itself (so Esc and
  // alt+u still work in the fingerprint-only view)
  function focusInput() { if (pwInput.enabled && pwInput.visible) pwInput.forceActiveFocus(); else root.forceActiveFocus(); }
  function clearInput() { pwInput.text = ""; }
  function shake() { shakeAnim.restart(); }
  function reset() { pwInput.text = ""; revealed = false; details = false; shakeX = 0; }

  Timer {
    interval: 80; repeat: true
    running: root.phase === "verifying"
    onTriggered: root.spinTick += 1
  }
  SequentialAnimation {
    id: shakeAnim
    NumberAnimation { target: root; property: "shakeX"; to: -8; duration: 45 }
    NumberAnimation { target: root; property: "shakeX"; to: 8; duration: 45 }
    NumberAnimation { target: root; property: "shakeX"; to: -6; duration: 45 }
    NumberAnimation { target: root; property: "shakeX"; to: 6; duration: 45 }
    NumberAnimation { target: root; property: "shakeX"; to: -3; duration: 45 }
    NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 45 }
  }

  // "... run `/usr/bin/foo -x' as ..." -> highlight the quoted subject.
  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
  readonly property string richMessage: {
    const m = /^([^`]*)`([^']*)'([\s\S]*)$/.exec(message);
    if (!m) return esc(message);
    return esc(m[1]) + "<font color=\"" + tone + "\">" + esc(m[2]) + "</font>" + esc(m[3]);
  }

  // fingerprint box colors by state
  readonly property color fpColor: fpState === "nomatch" ? Pal.red : fpState === "match" ? Pal.green : fpState === "listening" ? Pal.blue : Pal.faint
  readonly property string fpStatus: fpState === "nomatch" ? "not recognised · try again"
    : fpState === "match" ? "recognised"
    : fpState === "out" ? "unavailable · use your password" : "touch the sensor"
  readonly property real fpProgress: (fpState === "nomatch" || fpState === "match") ? 1 : 0

  Rectangle { anchors.fill: parent; color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.62) }
  // clicks on the scrim do nothing on purpose: a security prompt shouldn't
  // vanish because of a stray click -- Esc / [x] / cancel only.
  MouseArea { anchors.fill: parent }

  Rectangle {
    id: dialog
    width: Math.min(460, root.width - 32)
    x: (root.width - width) / 2 + root.shakeX
    y: Math.max(24, (root.height - height) / 2)
    height: body.implicitHeight + 20
    radius: 16
    color: Pal.card
    border.width: 1
    border.color: root.phase === "success" ? Pal.green : Pal.faint
    Behavior on border.color { ColorAnimation { duration: 200 } }

    MouseArea { anchors.fill: parent }

    ColumnLayout {
      id: body
      anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 10 }
      spacing: 0

      // header
      RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        spacing: 8
        PhIcon {
          name: root.phase === "success" ? "lock-simple-open" : "lock-simple"
          font.pixelSize: 15
          color: root.phase === "success" ? Pal.green : Pal.blue
        }
        Mono { text: "authenticate"; font.weight: Font.Medium; color: Pal.blue }
        Mono { text: "─ polkit ─"; color: Pal.muted }
        Item { Layout.fillWidth: true }
        TextButton {
          onClicked: root.cancelled()
          Mono { text: "[×]"; color: parent.parent.hovered ? Pal.red : Pal.muted }
        }
      }

      // request
      Box {
        Layout.fillWidth: true
        Layout.topMargin: 8
        padTop: 14; padSide: 10; padBottom: 10
        legend: "request"
        rightLegend: root.via
        rightColor: root.tone

        RowLayout {
          Layout.fillWidth: true
          spacing: 10
          Rectangle {
            Layout.preferredWidth: 36; Layout.preferredHeight: 36; Layout.alignment: Qt.AlignTop
            radius: 8
            color: Pal.edge
            PhIcon { anchors.centerIn: parent; name: root.glyph; font.pixelSize: 20; color: root.tone }
          }
          Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            font.family: Pal.mono; font.pixelSize: 12
            color: Pal.fg
            text: root.richMessage
          }
        }

        GridLayout {
          Layout.fillWidth: true
          Layout.topMargin: 10
          columns: 2
          columnSpacing: 10
          rowSpacing: 2
          Mono { text: "as"; color: Pal.muted; Layout.alignment: Qt.AlignVCenter }
          TextButton {
            Layout.alignment: Qt.AlignLeft
            Layout.leftMargin: -6
            hPad: 6
            enabled: root.identities.length > 1
            onClicked: if (root.identities.length > 1) root.cycleIdentity()
            Mono { text: root.userName; color: Pal.yellow }
            Mono { visible: root.identities.length > 0 && root.identities[root.identityIndex].note !== ""; text: root.identities.length ? root.identities[root.identityIndex].note : ""; color: Pal.muted }
            Mono { visible: root.identities.length > 1; text: "⇅"; color: Pal.muted }
          }
          Mono { text: "action"; color: Pal.muted }
          Mono { Layout.fillWidth: true; text: root.actionId; color: Pal.dim; wrapMode: Text.WrapAnywhere }
        }

        TextButton {
          Layout.topMargin: 4
          onClicked: root.details = !root.details
          Mono { text: (root.details ? "▾" : "▸") + " details"; color: parent.parent.hovered ? Pal.fg : Pal.muted }
        }
        Rectangle {
          visible: root.details
          Layout.fillWidth: true
          Layout.topMargin: 4
          implicitHeight: detailGrid.implicitHeight + 12
          radius: 2
          color: Pal.deep
          GridLayout {
            id: detailGrid
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
            columns: 2
            columnSpacing: 10
            rowSpacing: 1
            Repeater {
              model: root.detailRows
              delegate: Item {
                required property var modelData
                Layout.columnSpan: 2
                Layout.fillWidth: true
                implicitHeight: dv.implicitHeight
                Mono { text: modelData[0]; font.pixelSize: 11; color: Pal.muted }
                Mono { id: dv; x: 70; width: parent.width - 70; text: modelData[1]; font.pixelSize: 11; wrapMode: Text.WrapAnywhere }
              }
            }
          }
        }
      }

      // fingerprint (big: no password prompt yet)
      Box {
        visible: root.fpBig
        Layout.fillWidth: true
        Layout.topMargin: 16
        padTop: 20; padSide: 10; padBottom: 16
        legend: "fingerprint"; legendColor: root.fpState === "none" ? Pal.muted : root.fpColor
        rightLegend: root.fpMeta
        borderColor: root.fpState === "none" ? Pal.faint : root.fpColor

        FingerprintRing {
          Layout.alignment: Qt.AlignHCenter
          diameter: 84; glyphSize: 40
          progress: root.fpProgress
          arcColor: root.fpColor
          glyphColor: root.fpState === "listening" ? Pal.dim : root.fpColor
          halo: root.fpState === "listening"
        }
        ColumnLayout {
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: 10
          spacing: 0
          Mono { Layout.alignment: Qt.AlignHCenter; text: root.fpStatus; color: root.fpState === "listening" ? Pal.fg : root.fpColor }
          Mono { Layout.alignment: Qt.AlignHCenter; text: root.userName; color: Pal.muted }
        }
        // a failed attempt restarts the conversation at the sensor; keep
        // saying so here since the password box (and its message) is hidden
        Mono {
          visible: root.errorText !== ""
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: 6
          text: root.errorText
          color: Pal.red
        }
      }

      // password
      Box {
        visible: root.pwVisible
        Layout.fillWidth: true
        Layout.topMargin: 16
        padTop: 14; padSide: 10; padBottom: 10
        legend: /password/i.test(root.prompt) || root.prompt === "" ? "password" : root.prompt.replace(/[:\s]+$/, "").toLowerCase()
        legendColor: root.errorText ? Pal.red : Pal.muted
        rightLegend: "for " + root.userName
        borderColor: root.errorText ? Pal.red : Pal.faint

        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Mono {
            text: "❯"
            color: root.phase === "verifying" ? Pal.yellow : root.phase === "success" ? Pal.green : Pal.blue
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: pwInput.implicitHeight + 8
            color: pwInput.activeFocus ? Pal.raised : Pal.deep
            Rectangle {
              anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
              height: 1
              color: pwInput.activeFocus ? Pal.blue : Pal.faint
            }
            TextInput {
              id: pwInput
              anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
              verticalAlignment: TextInput.AlignVCenter
              font.family: Pal.mono; font.pixelSize: 12
              color: Pal.fg
              selectionColor: Pal.blue
              selectedTextColor: Pal.card
              echoMode: (root.revealed || root.echo) ? TextInput.Normal : TextInput.Password
              passwordCharacter: "•"
              enabled: root.responseRequired && !root.busy
              clip: true
              onTextChanged: if (text !== "") root.errorText = ""
              Keys.onReturnPressed: if (root.canSubmit) root.submitted(pwInput.text)
              Keys.onEnterPressed: if (root.canSubmit) root.submitted(pwInput.text)
              Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { root.cancelled(); e.accepted = true; }
                else if ((e.modifiers & Qt.AltModifier) && e.key === Qt.Key_U) { root.cycleIdentity(); e.accepted = true; }
              }
            }
            Mono {
              visible: pwInput.text === ""
              anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
              text: root.responseRequired ? "password for " + root.userName : "waiting…"
              color: Pal.muted
            }
          }
          TextButton {
            Layout.preferredWidth: 24; Layout.preferredHeight: 24
            hPad: 0
            onClicked: { root.revealed = !root.revealed; pwInput.forceActiveFocus(); }
            PhIcon {
              name: root.revealed ? "eye-slash" : "eye"
              font.pixelSize: 14
              color: parent.parent.hovered ? Pal.fg : Pal.muted
            }
          }
        }
        Mono {
          visible: text !== ""
          Layout.topMargin: 6
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          text: root.errorText || (root.fpCompact && root.fpState === "nomatch" ? "fingerprint unavailable — password required" : "")
          color: root.errorText ? Pal.red : Pal.yellow
        }
      }

      // fingerprint (compact, beside the password)
      Box {
        visible: root.fpCompact
        Layout.fillWidth: true
        Layout.topMargin: 16
        padTop: 14; padSide: 10; padBottom: 10
        legend: "fingerprint"; legendColor: root.fpState === "none" ? Pal.muted : root.fpColor
        rightLegend: root.fpMeta
        borderColor: root.fpState === "none" ? Pal.faint : root.fpColor

        RowLayout {
          Layout.fillWidth: true
          spacing: 12
          FingerprintRing {
            diameter: 46; thickness: 2; glyphSize: 24
            progress: root.fpProgress
            arcColor: root.fpColor
            glyphColor: root.fpState === "listening" ? Pal.dim : root.fpColor
          }
          ColumnLayout {
            spacing: 0
            Mono { text: root.fpStatus; color: root.fpState === "listening" ? Pal.fg : root.fpColor }
            Mono { text: "or type your password above"; color: Pal.muted }
          }
        }
      }

      // footer: key hints on their own line, buttons right-aligned beneath
      Hints {
        Layout.fillWidth: true
        Layout.topMargin: 14
        items: {
          const h = root.pwVisible && root.responseRequired ? [["\u23ce", "authenticate"]] : [["touch", "sensor"]];
          if (root.identities.length > 1) h.push(["alt u", "switch user"]);
          h.push(["esc", "cancel"]);
          return h;
        }
      }
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 6
        Item { Layout.fillWidth: true }
        TextButton {
          hPad: 10
          onClicked: root.cancelled()
          Mono { text: "< cancel >"; color: parent.parent.hovered ? Pal.fg : Pal.dim }
        }
        Rectangle {
          visible: root.pwVisible
          Layout.preferredWidth: authText.implicitWidth + 20
          Layout.preferredHeight: authText.implicitHeight
          radius: 2
          color: root.phase === "success" ? Pal.green : root.phase === "verifying" ? Pal.yellow : root.canSubmit ? Pal.blue : Pal.muted
          opacity: root.canSubmit || root.busy ? 1 : 0.5
          Behavior on color { ColorAnimation { duration: 200 } }
          Mono {
            id: authText
            anchors.centerIn: parent
            text: root.phase === "verifying" ? "< verifying " + root.spin + " >" : root.phase === "success" ? "< authorized \u2713 >" : "< authenticate >"
            font.weight: Font.Medium
            color: Pal.card
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.canSubmit) root.submitted(pwInput.text)
          }
        }
      }
    }
  }

  // Esc / alt+u when the password field doesn't have focus
  focus: true
  Keys.onPressed: (e) => {
    if (e.key === Qt.Key_Escape) { root.cancelled(); e.accepted = true; }
    else if ((e.modifiers & Qt.AltModifier) && e.key === Qt.Key_U) { root.cycleIdentity(); e.accepted = true; }
  }
  onPwVisibleChanged: Qt.callLater(focusInput)
  onResponseRequiredChanged: Qt.callLater(focusInput)
}

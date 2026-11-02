import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../widgets"

// ===== DISPLAY MODES (modal) =====
// Ported from example/Display Modes.dc.html, in the same shape as
// launcher/SshKeygenModal.qml: a full-screen Overlay window with exclusive
// keyboard focus, a dimmed scrim, and a 16px-radius card. State and logic
// live in DisplaysBackend.qml; this file is presentation only. Closing the
// modal quits the process.
PanelWindow {
  id: root

  readonly property alias backend: be

  // Pinned to the backend's chosen monitor (the laptop panel, or the
  // highest-resolution one when that is off). While outputs are being
  // reconfigured the screen list briefly changes, so the last matching
  // screen is kept rather than falling back to some other monitor.
  property var shownScreen: null
  function refreshScreen() {
    for (const s of Quickshell.screens) {
      if (s.name === be.uiName) { if (shownScreen !== s) shownScreen = s; return; }
    }
    if (!shownScreen && Quickshell.screens.length > 0) shownScreen = Quickshell.screens[0];
  }
  screen: shownScreen
  visible: be.ready
  Connections {
    target: be
    function onUiNameChanged() { root.refreshScreen(); }
  }
  Connections {
    target: Quickshell
    function onScreensChanged() { root.refreshScreen(); }
  }

  // Changing the layout throws the cursor onto another monitor. Once the
  // keep-or-revert panel is up, put it on the Keep button.
  Process { id: cursorProc }
  function warpToKeep() {
    const scr = root.screen;
    if (!scr || !primaryBtn.visible) return;
    const p = primaryBtn.mapToItem(null, primaryBtn.width / 2, primaryBtn.height / 2);
    cursorProc.command = ["hyprctl", "dispatch", "movecursor", String(Math.round(scr.x + p.x)), String(Math.round(scr.y + p.y))];
    cursorProc.running = true;
  }
  Connections {
    target: be
    function onConfirmShown() { Qt.callLater(root.warpToKeep); }
  }

  DisplaysBackend {
    id: be
    onQuitRequested: Qt.quit()
  }

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "coel-displays"

  Component.onCompleted: { refreshScreen(); Qt.callLater(() => keys.forceActiveFocus()); }

  // ----- keyboard -----
  Item {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.onPressed: (e) => {
      if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier)) return;
      let k = e.text;
      switch (e.key) {
        case Qt.Key_Escape: k = "Escape"; break;
        case Qt.Key_Return: case Qt.Key_Enter: k = "Enter"; break;
        case Qt.Key_Up: k = "ArrowUp"; break;
        case Qt.Key_Down: k = "ArrowDown"; break;
        case Qt.Key_Left: k = "ArrowLeft"; break;
        case Qt.Key_Right: k = "ArrowRight"; break;
      }
      if (be.handleKey(k)) e.accepted = true;
    }
  }

  // ----- scrim -----
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(24 / 255, 26 / 255, 31 / 255, 0.62)
    MouseArea { anchors.fill: parent; onClicked: if (be.phase === "pick") be.close() }
  }

  // ----- dialog -----
  Rectangle {
    id: dialog
    visible: be.ready
    width: Math.min(660, root.width - 32)
    x: (root.width - width) / 2
    y: Math.max(24, (root.height - height) / 2)
    height: dialogCol.implicitHeight + 20
    radius: Globals.eyeCandyOff ? 0 : 16
    color: Pal.card
    border.width: 1
    border.color: be.confirming ? Pal.blue : Pal.faint
    Behavior on border.color { ColorAnimation { duration: Globals.eyeCandyOff ? 0 : 200 } }

    MouseArea { anchors.fill: parent }

    ColumnLayout {
      id: dialogCol
      anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 10 }
      spacing: 0

      // header
      RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        spacing: 8
        PhIcon { name: "monitor"; font.pixelSize: 15; color: Pal.blue }
        Mono { text: "displays"; font.weight: Font.Medium; color: Pal.blue }
        Mono { text: "─ hyprctl ─"; color: Pal.muted }
        Mono { Layout.fillWidth: true; text: be.countLabel; color: Pal.dim; elide: Text.ElideRight }
        TextButton {
          onClicked: { if (be.confirming) be.revert(false); else if (!be.applying) be.close(); }
          Mono { text: "[×]"; color: parent.parent.hovered ? Pal.red : Pal.muted }
        }
      }

      // ----- pick -----
      ColumnLayout {
        visible: be.phase === "pick"
        Layout.fillWidth: true
        spacing: 0

        // layout canvas
        Box {
          Layout.fillWidth: true
          Layout.topMargin: 8
          padTop: 14; padSide: 10; padBottom: 10
          legend: "layout"
          rightLegend: be.canvasMeta
          rightColor: be.canvasMetaColor

          Rectangle {
            id: stage
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(width * 0.36)
            radius: Globals.eyeCandyOff ? 0 : 4
            color: Pal.deep
            border.width: 1
            border.color: Pal.faint
            clip: true

            Repeater {
              model: be.monitors
              delegate: Item {
                id: mon
                required property var modelData
                readonly property var g: be.canvas.byId[modelData.id]
                readonly property bool sel: be.selId === modelData.id
                // Last placed geometry, held while the monitor is not on the canvas.
                property real gl: 0
                property real gt: 0
                property real gw: 0
                property real gh: 0
                function sync() { if (g) { gl = g.l; gt = g.t; gw = g.w; gh = g.h; } }
                onGChanged: sync()
                Component.onCompleted: sync()

                visible: !!g
                x: gl * stage.width
                y: gt * stage.height
                width: gw * stage.width
                height: gh * stage.height
                Behavior on x { NumberAnimation { duration: Globals.eyeCandyOff ? 0 : 250; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Globals.eyeCandyOff ? 0 : 250; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Globals.eyeCandyOff ? 0 : 250; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: Globals.eyeCandyOff ? 0 : 250; easing.type: Easing.OutCubic } }

                // selection glow
                Rectangle {
                  visible: mon.sel
                  anchors.fill: parent
                  anchors.margins: -4
                  radius: Globals.eyeCandyOff ? 0 : 7
                  color: mon.modelData.color
                  opacity: 0.2
                }
                Rectangle {
                  anchors.fill: parent
                  radius: Globals.eyeCandyOff ? 0 : 3
                  color: Pal.card
                  border.width: mon.sel ? 2 : 1
                  border.color: mon.modelData.color
                  clip: true

                  ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    spacing: 0
                    RowLayout {
                      Layout.alignment: Qt.AlignHCenter
                      spacing: 4
                      PhIcon { name: mon.modelData.icon; font.pixelSize: 11; color: mon.modelData.color }
                      Mono { text: mon.modelData.id; font.pixelSize: 11; color: mon.modelData.color }
                    }
                    Mono {
                      Layout.alignment: Qt.AlignHCenter
                      text: mon.g ? mon.g.sub : ""
                      font.pixelSize: 10
                      color: Pal.muted
                    }
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: be.selectRow(be.rowIds().indexOf(mon.modelData.id))
                  }
                }
              }
            }

            Mono { visible: !be.valid; anchors.centerIn: parent; text: "no display on"; color: Pal.red }
          }

          Mono {
            visible: be.sideNote !== ""
            Layout.fillWidth: true
            Layout.topMargin: 6
            wrapMode: Text.Wrap
            text: be.sideNote
            color: Pal.muted
          }
        }

        // presets
        Flow {
          visible: be.presets.length > 0
          Layout.fillWidth: true
          Layout.topMargin: 12
          spacing: 4
          Mono { text: "presets"; color: Pal.muted; rightPadding: 4 }
          Repeater {
            model: be.presets
            delegate: ChipButton {
              required property var modelData
              label: modelData.label
              selected: modelData.on
              onClicked: be.preset(modelData.id)
            }
          }
        }

        // monitor rows
        Box {
          Layout.fillWidth: true
          Layout.topMargin: 16
          padTop: 12; padSide: 4; padBottom: 4
          legend: "monitors"
          rightLegend: "placed in the order you pick"

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Repeater {
              model: be.rows
              delegate: Rectangle {
                id: rowItem
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: Math.max(rowLay.implicitHeight, chipRow.implicitHeight) + 12
                radius: Globals.eyeCandyOff ? 0 : 4
                color: modelData.sel ? Pal.raised : "transparent"

                MouseArea { anchors.fill: parent; onClicked: be.selectRow(rowItem.index) }

                // Monitor info on the left, slot chips pinned to the right edge.
                RowLayout {
                  id: rowLay
                  anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
                  spacing: 8
                  Mono { Layout.preferredWidth: 8; text: rowItem.modelData.sel ? "▌" : ""; color: Pal.blue }
                  PhIcon { name: rowItem.modelData.icon; font.pixelSize: 15; color: rowItem.modelData.color }
                  ColumnLayout {
                    spacing: 0
                    Row {
                      spacing: 6
                      Mono { text: rowItem.modelData.id; color: rowItem.modelData.color }
                      Mono { text: rowItem.modelData.model; color: Pal.muted }
                    }
                    Row {
                      spacing: 0
                      // Click the mode to step through the monitor's modes.
                      TextButton {
                        hPad: 0
                        enabled: rowItem.modelData.canCycle
                        onClicked: be.cycleMode(rowItem.modelData.id, 1)
                        Mono {
                          text: rowItem.modelData.spec
                          font.pixelSize: 11
                          color: rowItem.modelData.warn ? Pal.orange : rowItem.modelData.modeChanged ? Pal.yellow : (parent.parent.hovered && rowItem.modelData.canCycle ? Pal.fg : Pal.muted)
                        }
                      }
                      Mono { text: " · "; font.pixelSize: 11; color: Pal.muted }
                      Mono { text: rowItem.modelData.pos; font.pixelSize: 11; color: rowItem.modelData.posColor }
                      Mono { visible: rowItem.modelData.warn; text: "  ⚠ stretched"; font.pixelSize: 11; color: Pal.orange }
                      TextButton {
                        visible: rowItem.modelData.warn && rowItem.modelData.canFit
                        hPad: 4
                        onClicked: be.fitMode(rowItem.modelData.id)
                        Mono { text: "[fit]"; font.pixelSize: 11; color: parent.parent.hovered ? Pal.fg : Pal.orange }
                      }
                    }
                  }
                }

                Row {
                  id: chipRow
                  anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 6 }
                  spacing: 3
                  Repeater {
                    model: rowItem.modelData.opts
                    delegate: ChipButton {
                      required property var modelData
                      label: modelData.label
                      selected: modelData.selected
                      dimmed: modelData.dimmed
                      accent: rowItem.modelData.color
                      hPad: 7
                      onClicked: be.pickSlot(rowItem.modelData.id, modelData.k, modelData.dimmed)
                    }
                  }
                  Row {
                    visible: rowItem.modelData.reorder
                    leftPadding: 4
                    spacing: 1
                    Repeater {
                      model: rowItem.modelData.arrows
                      delegate: TextButton {
                        required property var modelData
                        hPad: 4
                        opacity: modelData.off ? 0.35 : 1
                        onClicked: if (!modelData.off) be.nudge(rowItem.modelData.id, modelData.delta)
                        Mono { text: "[" + modelData.glyph + "]"; color: parent.parent.hovered ? Pal.fg : Pal.dim }
                      }
                    }
                  }

                }
              }
            }
          }
        }

        // commands
        Box {
          Layout.fillWidth: true
          Layout.topMargin: 16
          padTop: 12; padSide: 10; padBottom: 6
          legend: "runs"
          rightLegend: be.diffLabel
          rightColor: be.diffColor

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Repeater {
              model: be.cmd
              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Mono { Layout.preferredWidth: 12; Layout.alignment: Qt.AlignTop; text: "$"; font.pixelSize: 11; color: Pal.muted }
                Mono { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; text: modelData; font.pixelSize: 11; color: Pal.dim }
              }
            }
          }
        }
      }

      // ----- applying / confirm -----
      Box {
        visible: be.applying || be.confirming
        Layout.fillWidth: true
        Layout.topMargin: 8
        padTop: 16; padSide: 12; padBottom: 12
        borderColor: be.cf.border
        legend: be.cf.legend
        legendColor: be.cf.legendColor
        rightLegend: be.cf.meta

        RowLayout {
          Layout.fillWidth: true
          spacing: 14
          PhIcon { name: be.cf.icon; font.pixelSize: 28; color: be.cf.color }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Mono { Layout.fillWidth: true; wrapMode: Text.Wrap; text: be.cf.title }
            Mono { Layout.fillWidth: true; wrapMode: Text.Wrap; text: be.cf.sub; color: Pal.muted }
          }
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.topMargin: 12
          Layout.preferredHeight: 6
          radius: Globals.eyeCandyOff ? 0 : 1
          color: Pal.track
          clip: true
          Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * be.cf.pct
            color: be.cf.barColor
            Behavior on width { NumberAnimation { duration: Globals.eyeCandyOff ? 0 : 1000 } }
          }
        }
      }

      // ----- footer -----
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 14
        spacing: 12
        Hints {
          Layout.fillWidth: true
          items: be.hints
        }
        TextButton {
          hPad: 10
          onClicked: be.confirming ? be.revert(false) : be.close()
          Mono { text: "< " + be.secondaryLabel + " >"; color: parent.parent.hovered ? Pal.fg : Pal.dim }
        }
        Rectangle {
          id: primaryBtn
          Layout.preferredWidth: primaryText.implicitWidth + 20
          Layout.preferredHeight: primaryText.implicitHeight
          radius: Globals.eyeCandyOff ? 0 : 2
          color: be.primaryBg
          opacity: be.primaryOpacity
          Mono {
            id: primaryText
            anchors.centerIn: parent
            text: "< " + be.primaryLabel + " >"
            font.weight: Font.Medium
            color: Pal.card
          }
          MouseArea {
            anchors.fill: parent
            enabled: !be.primaryDisabled
            cursorShape: Qt.PointingHandCursor
            onClicked: be.confirming ? be.keep() : be.apply()
          }
        }
      }
    }
  }
}

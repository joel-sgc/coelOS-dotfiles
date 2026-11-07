import QtQuick
import QtQuick.Layouts
import "../.."
import "../Phosphor.js" as Phosphor
import "../components"

// ===== ETHERNET VIEW =====
// The "3 ethernet" tab of the network dropdown, ported from the design mock
// (example/Quickshell Bar.dc.html, `isEth`). Pure UI: everything it shows
// and every button it calls comes from `be.vals` (EthernetBackend.qml).
//
//   interfaces   one row per wired port / vlan, with its role and link state
//   <port> role  role tabs, that role's settings, apply / revert / test
//   job          the live log of the last apply or diagnostic run
//   clients      leases handed out while this port is sharing
//   routes       the IPv4 routing table, best default route marked
//
// Rows that mix several fixed-width columns use manual positioning (see
// PowerDropdown.qml's profile-row comment for why not RowLayout).
Item {
  id: view

  property var be
  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property int maxHeight: 700

  readonly property var v: be ? be.vals : ({ empty: true, rows: [], routes: [] })
  readonly property string mono: "JetBrains Mono"

  implicitHeight: Math.min(flick.contentHeight, maxHeight)

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: flick.width
      spacing: 16

      Item { width: 1; height: 0 }

      // ----- interfaces -----
      Section {
        width: parent.width
        label: "interfaces (" + view.v.count + ")"
        labelColor: "#2bbac5"
        paddingSide: 4
        spacing: 2
        rightContent: [
          Text {
            text: "[v] +vlan"
            color: addVlanMouse.containsMouse ? view.fgColor : view.mutedColor
            font.family: view.mono
            font.pixelSize: 13
            MouseArea { id: addVlanMouse; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.be.addVlan() }
          }
        ]

        Item {
          width: parent.width
          height: 18
          Text { x: 22; anchors.verticalCenter: parent.verticalCenter; text: "iface"; color: view.mutedColor; font.family: view.mono; font.pixelSize: 12 }
          Text { x: parent.width - 62 - 8 - 98 - 8 - 92; anchors.verticalCenter: parent.verticalCenter; text: "hw"; color: view.mutedColor; font.family: view.mono; font.pixelSize: 12 }
          Text { x: parent.width - 62 - 8 - 98; anchors.verticalCenter: parent.verticalCenter; text: "link"; color: view.mutedColor; font.family: view.mono; font.pixelSize: 12 }
          Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "role"; color: view.mutedColor; font.family: view.mono; font.pixelSize: 12 }
        }

        Repeater {
          model: view.v.rows
          delegate: Rectangle {
            id: ifRow
            required property var modelData
            width: parent.width
            height: 20
            radius: Globals.eyeCandyOff ? 0 : 2
            color: modelData.sel ? "#2f343e" : (rowMouse.containsMouse ? "#2f343e" : "transparent")

            Text { x: 4; anchors.verticalCenter: parent.verticalCenter; text: ifRow.modelData.sel ? "▌" : ""; color: "#2bbac5"; font.family: view.mono; font.pixelSize: 13 }
            Text {
              id: ifIcon
              x: 22
              anchors.verticalCenter: parent.verticalCenter
              text: Phosphor.icon(ifRow.modelData.iconName)
              color: ifRow.modelData.iconColor
              font.family: "Phosphor"
              font.pixelSize: 13
            }
            Text {
              id: ifName
              anchors.left: ifIcon.right
              anchors.leftMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, hwText.x - x - 28)
              elide: Text.ElideRight
              text: ifRow.modelData.name
              color: view.fgColor
              font.family: view.mono
              font.pixelSize: 13
            }
            Text {
              visible: ifRow.modelData.isInet
              anchors.left: ifName.right
              anchors.leftMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              text: Phosphor.icon("globe-simple")
              color: "#89ca78"
              font.family: "Phosphor"
              font.pixelSize: 12
            }
            Text {
              id: hwText
              x: parent.width - 62 - 8 - 98 - 8 - 92
              width: 92
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: ifRow.modelData.kind
              color: view.mutedColor
              font.family: view.mono
              font.pixelSize: 12
            }
            Text {
              x: parent.width - 62 - 8 - 98
              width: 98
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: ifRow.modelData.link
              color: ifRow.modelData.linkColor
              font.family: view.mono
              font.pixelSize: 13
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              text: ifRow.modelData.role
              color: ifRow.modelData.roleColor
              font.family: view.mono
              font.pixelSize: 13
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: ifRow.modelData.select()
            }
          }
        }
        Text {
          visible: view.v.count === 0
          x: 8
          text: "no wired ports found"
          color: view.mutedColor
          font.family: view.mono
          font.pixelSize: 13
        }
      }

      // ----- selected port: role + settings -----
      Section {
        visible: !view.v.empty
        width: parent.width
        label: view.v.empty ? "" : view.v.selName + " ─ role"
        labelColor: view.v.empty ? "#5c6370" : view.v.roleColor
        paddingTop: 14
        paddingBottom: 12
        paddingSide: 12
        spacing: 6
        rightContent: [
          Text { text: view.v.empty ? "" : view.v.state; color: view.v.empty ? "#5c6370" : view.v.stateColor; font.family: view.mono; font.pixelSize: 13 }
        ]

        Flow {
          width: parent.width
          spacing: 2
          Repeater {
            model: view.v.empty ? [] : view.v.roleTabs
            delegate: Rectangle {
              id: tab
              required property var modelData
              implicitWidth: tabRow.implicitWidth + 16
              implicitHeight: 20
              radius: Globals.eyeCandyOff ? 0 : 2
              color: modelData.active ? view.hoverColor : (tabMouse.containsMouse ? "#2f343e" : "transparent")
              Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: 6
                Text { text: tab.modelData.key; color: "#e5c07b"; font.family: view.mono; font.pixelSize: 13 }
                Text { text: tab.modelData.label; color: tabMouse.containsMouse && !tab.modelData.active ? view.fgColor : tab.modelData.color; font.family: view.mono; font.pixelSize: 13 }
              }
              MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.modelData.pick() }
            }
          }
        }

        Text {
          width: parent.width
          topPadding: 4
          bottomPadding: 4
          wrapMode: Text.WordWrap
          text: view.v.empty ? "" : view.v.roleDesc
          color: view.mutedColor
          font.family: view.mono
          font.pixelSize: 12
        }

        // The model is the *count*: each delegate reads its own field live from
        // be.vals, so an edit that only changes values never rebuilds the rows
        // (rebuilding would drop focus from the text input being typed in).
        ColumnLayout {
          width: parent.width
          spacing: 6
          Repeater {
            model: view.v.empty ? 0 : view.v.fields.length
            delegate: ColumnLayout {
              id: fieldRow
              required property int index
              readonly property var f: view.v.empty || index >= view.v.fields.length ? ({ type: "note", label: "", value: "", color: "#5c6370", indent: 0 }) : view.v.fields[index]
              Layout.fillWidth: true
              spacing: 0

              FormField {
                visible: fieldRow.f.type === "cycle" || fieldRow.f.type === "input"
                Layout.leftMargin: fieldRow.f.indent
                label: fieldRow.f.label
                labelWidth: 130 - fieldRow.f.indent
                mode: fieldRow.f.type === "cycle" ? "cycle" : (fieldRow.f.password ? "password" : "text")
                value: fieldRow.f.type === "cycle" || fieldRow.f.type === "input" ? fieldRow.f.value : ""
                placeholder: fieldRow.f.ph || ""
                showToggle: !!fieldRow.f.hasShow
                fgColor: view.fgColor
                labelColor: view.mutedColor
                hoverColor: view.hoverColor
                accentColor: "#2bbac5"
                onValueEdited: (nv) => fieldRow.f.change(nv)
                onCycled: fieldRow.f.cycle()
                onToggleVisibility: fieldRow.f.toggleShow()
                onAccepted: view.be.apply()
              }

              RowLayout {
                visible: fieldRow.f.type === "checks"
                Layout.fillWidth: true
                spacing: 12
                Text { visible: fieldRow.f.label !== ""; Layout.preferredWidth: 118; text: fieldRow.f.label; color: view.mutedColor; font.family: view.mono; font.pixelSize: 13 }
                Flow {
                  Layout.fillWidth: true
                  spacing: 18
                  Repeater {
                    model: fieldRow.f.type === "checks" ? fieldRow.f.checks : []
                    delegate: Item {
                      id: chk
                      required property var modelData
                      implicitWidth: chkRow.implicitWidth
                      implicitHeight: 18
                      Row {
                        id: chkRow
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: chk.modelData.box; color: chk.modelData.color; font.family: view.mono; font.pixelSize: 13 }
                        Text { text: chk.modelData.label; color: chkMouse.containsMouse ? "#2bbac5" : view.fgColor; font.family: view.mono; font.pixelSize: 13 }
                      }
                      MouseArea { id: chkMouse; anchors.fill: parent; enabled: chk.modelData.box !== ""; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chk.modelData.toggle() }
                    }
                  }
                }
              }

              RowLayout {
                visible: fieldRow.f.type === "note"
                Layout.fillWidth: true
                spacing: 12
                Text { Layout.preferredWidth: 118; text: fieldRow.f.label; color: view.mutedColor; font.family: view.mono; font.pixelSize: 13 }
                Text {
                  Layout.fillWidth: true
                  wrapMode: Text.WordWrap
                  text: fieldRow.f.type === "note" ? fieldRow.f.value : ""
                  color: fieldRow.f.type === "note" ? fieldRow.f.color : "#5c6370"
                  font.family: view.mono
                  font.pixelSize: 12
                }
              }
            }
          }
        }

        // actions
        Flow {
          width: parent.width
          topPadding: 8
          spacing: 8

          Rectangle {
            implicitWidth: applyLabel.implicitWidth + 20
            implicitHeight: 22
            radius: Globals.eyeCandyOff ? 0 : 2
            color: view.v.empty ? "#404754" : view.v.applyColor
            opacity: !view.v.empty && view.v.applyEnabled ? 1 : 0.6
            Text { id: applyLabel; anchors.centerIn: parent; text: view.v.empty ? "" : view.v.applyLabel; color: "#282c34"; font.family: view.mono; font.weight: Font.DemiBold; font.pixelSize: 13 }
            MouseArea { anchors.fill: parent; enabled: !view.v.empty && view.v.applyEnabled; cursorShape: Qt.PointingHandCursor; onClicked: view.v.apply() }
          }
          Rectangle {
            visible: !view.v.empty && view.v.dirty
            implicitWidth: revertLabel.implicitWidth + 20
            implicitHeight: 22
            radius: Globals.eyeCandyOff ? 0 : 2
            color: revertMouse.containsMouse ? view.hoverColor : "transparent"
            Text { id: revertLabel; anchors.centerIn: parent; text: "< revert >"; color: view.fgColor; font.family: view.mono; font.pixelSize: 13 }
            MouseArea { id: revertMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.v.revert() }
          }
          Rectangle {
            implicitWidth: testRow.implicitWidth + 20
            implicitHeight: 22
            radius: Globals.eyeCandyOff ? 0 : 2
            color: testMouse.containsMouse ? view.hoverColor : "transparent"
            Row {
              id: testRow
              anchors.centerIn: parent
              spacing: 0
              Text { text: "< "; color: view.fgColor; font.family: view.mono; font.pixelSize: 13 }
              Text { text: "t"; color: "#e5c07b"; font.family: view.mono; font.pixelSize: 13 }
              Text { text: "est >"; color: view.fgColor; font.family: view.mono; font.pixelSize: 13 }
            }
            MouseArea { id: testMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.be.test() }
          }
          Rectangle {
            implicitWidth: advLabel.implicitWidth + 12
            implicitHeight: 22
            color: "transparent"
            Text { id: advLabel; anchors.centerIn: parent; text: view.v.advLabel; color: advMouse.containsMouse ? view.fgColor : view.mutedColor; font.family: view.mono; font.pixelSize: 13 }
            MouseArea { id: advMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.be.adv = !view.be.adv }
          }
          Rectangle {
            visible: !view.v.empty && view.v.canDelete
            implicitWidth: delLabel.implicitWidth + 20
            implicitHeight: 22
            radius: Globals.eyeCandyOff ? 0 : 2
            color: delMouse.containsMouse ? view.hoverColor : "transparent"
            Text { id: delLabel; anchors.centerIn: parent; text: "< delete vlan >"; color: "#ef596f"; font.family: view.mono; font.pixelSize: 13 }
            MouseArea { id: delMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.v.deleteVlan() }
          }
        }

        // live info for the port's current role
        Item {
          visible: !view.v.empty && view.v.hasInfo
          width: parent.width
          height: visible ? infoGrid.implicitHeight + 16 : 0
          Rectangle { width: parent.width; y: 4; height: 1; color: "#3e4451" }
          GridLayout {
            id: infoGrid
            y: 12
            width: parent.width
            columns: 4
            columnSpacing: 12
            rowSpacing: 1
            Repeater {
              model: view.v.empty ? [] : view.v.info
              delegate: Item {
                id: kv
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.columnSpan: 2
                implicitHeight: 17
                Text { id: kvKey; anchors.verticalCenter: parent.verticalCenter; text: kv.modelData.k; color: view.mutedColor; font.family: view.mono; font.pixelSize: 12 }
                Text {
                  anchors.left: kvKey.right
                  anchors.leftMargin: 12
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: kv.modelData.v
                  color: view.fgColor
                  font.family: view.mono
                  font.pixelSize: 13
                }
              }
            }
          }
        }
      }

      // ----- job log -----
      Section {
        visible: view.v.job !== null && view.v.job !== undefined
        width: parent.width
        label: view.v.job ? view.v.job.title : ""
        labelColor: "#e5c07b"
        paddingTop: 12
        paddingBottom: 8
        paddingSide: 12
        spacing: 1
        rightContent: [
          Text {
            text: view.v.job ? view.v.job.right : ""
            color: jobMouse.containsMouse ? view.fgColor : view.mutedColor
            font.family: view.mono
            font.pixelSize: 13
            MouseArea { id: jobMouse; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.v.dismissJob() }
          }
        ]

        Repeater {
          model: view.v.job ? view.v.job.lines : []
          delegate: Item {
            id: jl
            required property var modelData
            width: parent.width
            height: 18
            Text { x: 0; anchors.verticalCenter: parent.verticalCenter; text: jl.modelData.mark; color: jl.modelData.color; font.family: view.mono; font.pixelSize: 13 }
            Text { id: jlRes; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: jl.modelData.result; color: jl.modelData.color; font.family: view.mono; font.pixelSize: 13 }
            Text {
              x: 24
              anchors.right: jlRes.left
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: jl.modelData.label
              color: jl.modelData.textColor
              font.family: view.mono
              font.pixelSize: 13
            }
          }
        }
      }

      // ----- clients -----
      Section {
        visible: !view.v.empty && view.v.serving
        width: parent.width
        label: "clients (" + (view.v.leaseCount || 0) + ")"
        labelColor: "#d19a66"
        paddingSide: 4
        spacing: 2
        rightContent: [
          Text { text: view.v.pool || ""; color: view.mutedColor; font.family: view.mono; font.pixelSize: 13 }
        ]

        Text {
          visible: !view.v.leases || view.v.leases.length === 0
          x: 8
          text: "○ no leases yet — waiting for DHCP requests"
          color: view.mutedColor
          font.family: view.mono
          font.pixelSize: 13
        }
        Repeater {
          model: view.v.leases || []
          delegate: Rectangle {
            id: lease
            required property var modelData
            width: parent.width
            height: 19
            radius: Globals.eyeCandyOff ? 0 : 2
            color: leaseMouse.containsMouse ? "#2f343e" : "transparent"
            Text { id: leaseDot; x: 8; anchors.verticalCenter: parent.verticalCenter; text: lease.modelData.online ? "●" : "○"; color: lease.modelData.online ? "#89ca78" : view.mutedColor; font.family: view.mono; font.pixelSize: 13 }
            Text { id: leaseLeft; anchors.right: parent.right; anchors.rightMargin: 8; width: 38; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: lease.modelData.left; color: view.mutedColor; font.family: view.mono; font.pixelSize: 12 }
            Text { id: leaseMac; anchors.right: leaseLeft.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: lease.modelData.mac; color: view.mutedColor; font.family: view.mono; font.pixelSize: 12 }
            Text { id: leaseIp; anchors.right: leaseMac.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: lease.modelData.ip; color: view.fgColor; font.family: view.mono; font.pixelSize: 13 }
            Text {
              anchors.left: leaseDot.right
              anchors.leftMargin: 6
              anchors.right: leaseIp.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: lease.modelData.name
              color: view.fgColor
              font.family: view.mono
              font.pixelSize: 13
            }
            MouseArea { id: leaseMouse; anchors.fill: parent; hoverEnabled: true }
          }
        }
      }

      // ----- routes -----
      Section {
        width: parent.width
        label: "routes"
        labelColor: "#61afef"
        paddingSide: 4
        spacing: 1
        rightContent: [
          Text { text: view.v.inetLabel || ""; color: view.v.inetColor || view.mutedColor; font.family: view.mono; font.pixelSize: 13 }
        ]

        Repeater {
          model: view.v.routes
          delegate: Item {
            id: rt
            required property var modelData
            width: parent.width
            height: 17
            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: rt.modelData.mark; color: "#89ca78"; font.family: view.mono; font.pixelSize: 13 }
            Text { x: 24; width: 128; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: rt.modelData.dest; color: rt.modelData.color; font.family: view.mono; font.pixelSize: 13 }
            Text { id: rtMetric; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: rt.modelData.metric; color: view.mutedColor; font.family: view.mono; font.pixelSize: 12 }
            Text {
              x: 24 + 128 + 8
              anchors.right: rtMetric.left
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: rt.modelData.via
              color: view.mutedColor
              font.family: view.mono
              font.pixelSize: 12
            }
          }
        }
      }

      Item { width: 1; height: 2 }
    }
  }
}

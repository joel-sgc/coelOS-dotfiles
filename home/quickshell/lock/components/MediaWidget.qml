import QtQuick
import "../.."
import QtQuick.Layouts
import "../../sysPanel/Phosphor.js" as Phosphor

// ===== MEDIA WIDGET =====
// Top-left transport controls in the "1a Corner" mockup. Fed by Lock.qml's
// fake, Timer-driven playback state -- no real MPRIS backend yet (none
// exists anywhere in this repo; that's real backend work, explicitly
// deferred per the lock-screen plan, kept in the layout so it doesn't need
// redesigning once it lands). Icon-only buttons match the mock's own
// hover-background treatment (padding:4px;border-radius:6px), not
// sysPanel/buttons/Button.qml's chrome -- that component hardcodes its
// icon color to an ambient `root.fgColor` with no per-instance override,
// which this needs (dim skip icons vs. accent-colored play/pause).
RowLayout {
  id: root

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property color accentColor: "#61afef"

  property bool playing: true
  property string title: ""
  property string artist: ""
  property int posSeconds: 0
  property int durSeconds: 1

  signal prevRequested()
  signal nextRequested()
  signal toggleRequested()

  function mmss(total) {
    const m = Math.floor(total / 60), s = total % 60;
    return m + ":" + String(s).padStart(2, "0");
  }

  spacing: 14

  RowLayout {
    spacing: 2

    Rectangle {
      implicitWidth: 22
      implicitHeight: 22
      radius: Globals.eyeCandyOff ? 0 : 6
      color: prevMouse.containsMouse ? root.hoverColor : "transparent"
      Text {
        anchors.centerIn: parent
        text: Phosphor.icon("skip-back")
        color: prevMouse.containsMouse ? root.fgColor : root.mutedColor
        font.family: "Phosphor"
        font.pixelSize: 14
      }
      MouseArea {
        id: prevMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.prevRequested()
      }
    }

    Rectangle {
      implicitWidth: 24
      implicitHeight: 24
      radius: Globals.eyeCandyOff ? 0 : 6
      color: toggleMouse.containsMouse ? root.hoverColor : "transparent"
      Text {
        anchors.centerIn: parent
        text: root.playing ? Phosphor.icon("pause") : Phosphor.icon("play")
        color: toggleMouse.containsMouse ? root.accentColor : root.fgColor
        font.family: "Phosphor"
        font.pixelSize: 16
      }
      MouseArea {
        id: toggleMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleRequested()
      }
    }

    Rectangle {
      implicitWidth: 22
      implicitHeight: 22
      radius: Globals.eyeCandyOff ? 0 : 6
      color: nextMouse.containsMouse ? root.hoverColor : "transparent"
      Text {
        anchors.centerIn: parent
        text: Phosphor.icon("skip-forward")
        color: nextMouse.containsMouse ? root.fgColor : root.mutedColor
        font.family: "Phosphor"
        font.pixelSize: 14
      }
      MouseArea {
        id: nextMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.nextRequested()
      }
    }
  }

  ColumnLayout {
    spacing: 5

    RowLayout {
      spacing: 0
      Text {
        text: root.title
        color: root.fgColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }
      Text {
        text: " — " + root.artist
        color: root.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 13
      }
    }

    RowLayout {
      spacing: 8
      Item {
        implicitWidth: 140
        implicitHeight: 3
        Rectangle {
          anchors.fill: parent
          radius: Globals.eyeCandyOff ? 0 : 2
          color: root.hoverColor
        }
        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          radius: Globals.eyeCandyOff ? 0 : 2
          color: root.accentColor
          width: parent.width * Math.max(0, Math.min(1, root.posSeconds / Math.max(1, root.durSeconds)))
        }
      }
      Text {
        text: root.mmss(root.posSeconds) + " / " + root.mmss(root.durSeconds)
        color: root.mutedColor
        font.family: "JetBrains Mono"
        font.pixelSize: 11
      }
    }
  }
}

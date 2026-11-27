import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "data"

// Seamless login, session side. After the password, the login screen settles
// back into the boot picture (COELOS wordmark centred on flat #282c34, the same
// frame Plymouth ends on; greeter/Greeter.qml outro) and that frame stays up
// while Hyprland starts (its own first frames are that flat colour too). We open
// on exactly that picture, then the wordmark shrinks into the bar's logo while
// the colour dissolves into the desktop. If the greeting is due it takes over
// from here (DeskState.introActive holds it until we're done).
//
// Only on a real login: not a hot reload (PersistentProperties), and only while
// Hyprland itself is a few seconds old (a Quickshell restart mid-session must
// not replay it). Hyprland's own first frames are plain #282c34 (hyprland.lua
// misc), the login screen's base colour, so there's no logo flash before this.
Scope {
  id: si
  property var screen: null
  readonly property bool candy: !Globals.eyeCandyOff

  PersistentProperties {
    id: life
    reloadableId: "session-intro-life"
    property bool checked: false
  }
  property bool playing: false
  Component.onCompleted: {
    if (life.checked) return;
    life.checked = true;
    DeskState.introActive = true;   // hold the greeting until we know
    age.running = true;
  }
  // How long has Hyprland been running? Under 20 s means we're part of a login.
  Process {
    id: age
    command: ["sh", "-c", "ps -o etimes= -p \"$(pgrep -o -x Hyprland)\""]
    stdout: StdioCollector {
      onStreamFinished: {
        const s = parseInt(text.trim());
        if (!isNaN(s) && s < 20 && si.screen) si.play();
        else DeskState.introActive = false;
      }
    }
    onExited: (code) => { if (code !== 0) DeskState.introActive = false; }
  }

  // `quickshell ipc ... call sessionintro test` replays it (resets the picture first).
  IpcHandler {
    target: "sessionintro"
    function test(): void {
      seq.stop();
      mark.width = 730; mark.height = 160; mark.opacity = 1; backdrop.opacity = 1;
      mark.x = Math.floor(mark.parent.width / 2 - 365); mark.y = Math.floor(mark.parent.height / 2 - 80);
      si.play();
    }
  }
  function play() {
    playing = true;
    if (!candy) { stillTimer.start(); return; }
    seq.start();
  }
  function finish() { playing = false; DeskState.introActive = false; }
  Timer { id: stillTimer; interval: 500; onTriggered: si.finish() }

  SequentialAnimation {
    id: seq
    PauseAnimation { duration: 200 }   // the boot picture, held a beat
    ParallelAnimation {
      NumberAnimation { target: mark; property: "x"; to: 12; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
      NumberAnimation { target: mark; property: "y"; to: 8; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
      NumberAnimation { target: mark; property: "width"; to: 91; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
      NumberAnimation { target: mark; property: "height"; to: 20; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
      SequentialAnimation {
        PauseAnimation { duration: 300 }
        NumberAnimation { target: mark; property: "opacity"; to: 0; duration: 260 }
      }
      SequentialAnimation {
        PauseAnimation { duration: 120 }
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
      }
    }
    ScriptAction { script: si.finish() }
  }

  PanelWindow {
    screen: si.screen
    visible: si.playing
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "coel-session-intro"

    Rectangle { id: backdrop; anchors.fill: parent; color: "#282c34" }
    // No pointer while the splash dissolves (it comes back on the desktop).
    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton; cursorShape: Qt.BlankCursor }
    Image {
      id: mark
      source: Qt.resolvedUrl("../assets/coelos-wordmark.png")
      width: 730; height: 160
      x: Math.floor(parent.width / 2 - 365)
      y: Math.floor(parent.height / 2 - 80)
      smooth: true
    }
  }
}

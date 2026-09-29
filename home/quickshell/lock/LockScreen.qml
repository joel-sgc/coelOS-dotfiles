import QtQuick
import "./components"

// ===== LOCK SCREEN LAYOUT =====
// Pure layout: places the 4 corner regions of the "1a Corner" mockup
// (sddm-hyprlock/Lockscreen.dc.html) using its own literal fixed-pixel
// insets, anchored to whichever real screen this instance is drawn on.
// Every prop here is a straight pass-through between Lock.qml (which owns
// all the state) and the presentational components below -- same shape as
// Launcher.qml -> LauncherPanel.qml elsewhere in this project.
Item {
  id: root

  property color bgColor: "#282c34"
  property color fgColor: "#abb2bf"
  property color brightColor: "#d7dae0"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property color inputBg: "#1e2127"
  property color rowBg: "#2f343e"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]

  property string ssid: "home-5g"
  property int batteryPct: 82

  property bool playing: true
  property string mediaTitle: ""
  property string mediaArtist: ""
  property int mediaPos: 0
  property int mediaDur: 1
  signal mediaPrevRequested()
  signal mediaNextRequested()
  signal mediaToggleRequested()

  property string mode: "lock"
  property var users: []
  property int selectedUser: 0
  property var sessions: []
  property int selectedSession: 0
  property string lockedAtText: ""
  property string pw: ""
  property bool showPw: false
  property string authState: "idle"
  property var statusLine: ({ icon: "", text: "", color: "#5c6370" })
  property bool capsOn: false
  property string armedPower: ""
  property var powerActions: []
  property bool fpOn: true
  property int shakeSeq: 0

  signal pwEdited(string text)
  signal submitRequested()
  signal toggleShowRequested()
  signal pickUserRequested(int index)
  signal sessionStepRequested(int delta)
  signal switchModeRequested(string mode)
  signal powerRequested(var action)
  signal debugCapsToggleRequested()

  MediaWidget {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.topMargin: 28
    anchors.leftMargin: 40
    fgColor: root.fgColor
    mutedColor: root.mutedColor
    hoverColor: root.hoverColor
    accentColor: root.colors[0]
    playing: root.playing
    title: root.mediaTitle
    artist: root.mediaArtist
    posSeconds: root.mediaPos
    durSeconds: root.mediaDur
    onPrevRequested: root.mediaPrevRequested()
    onNextRequested: root.mediaNextRequested()
    onToggleRequested: root.mediaToggleRequested()
  }

  NetworkBattery {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 30
    anchors.rightMargin: 40
    fgColor: root.mutedColor
    ssid: root.ssid
    batteryPct: root.batteryPct
  }

  ClockDate {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: 56
    anchors.bottomMargin: 52
    fgColor: root.brightColor
    mutedColor: root.mutedColor
  }

  AuthCard {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: 56
    anchors.bottomMargin: 52
    fgColor: root.fgColor
    brightColor: root.brightColor
    mutedColor: root.mutedColor
    hoverColor: root.hoverColor
    inputBg: root.inputBg
    rowBg: root.rowBg
    colors: root.colors
    mode: root.mode
    users: root.users
    selectedUser: root.selectedUser
    sessions: root.sessions
    selectedSession: root.selectedSession
    lockedAtText: root.lockedAtText
    pw: root.pw
    showPw: root.showPw
    authState: root.authState
    statusLine: root.statusLine
    capsOn: root.capsOn
    armedPower: root.armedPower
    powerActions: root.powerActions
    fpOn: root.fpOn
    shakeSeq: root.shakeSeq
    onPwEdited: (text) => root.pwEdited(text)
    onSubmitRequested: root.submitRequested()
    onToggleShowRequested: root.toggleShowRequested()
    onPickUserRequested: (index) => root.pickUserRequested(index)
    onSessionStepRequested: (delta) => root.sessionStepRequested(delta)
    onSwitchModeRequested: (mode) => root.switchModeRequested(mode)
    onPowerRequested: (action) => root.powerRequested(action)
    onDebugCapsToggleRequested: root.debugCapsToggleRequested()
  }
}

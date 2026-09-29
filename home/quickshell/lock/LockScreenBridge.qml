// ===== LOCK SCREEN BRIDGE =====
// Thin wrapper so Lock.qml's two coexisting surface implementations (real
// WlSessionLockSurface vs. the dev-harness PanelWindow) don't each need
// their own full copy of every LockScreen prop binding. References
// `lockRoot` unqualified rather than declaring its own props -- same
// ambient-id idiom sysPanel/buttons/Button.qml already relies on for
// `root.fgColor`/`root.hoverColor` from deep inside Panel.qml's tree, and
// already proven through a Variants+Component boundary specifically by
// Launcher.qml's own PanelWindow delegate (`launcherScope.fgColor`) --
// this is one file layer deeper than that, not a different mechanism.
LockScreen {
    anchors.fill: parent
    bgColor: lockRoot.bgColor
    fgColor: lockRoot.fgColor
    brightColor: lockRoot.brightColor
    mutedColor: lockRoot.mutedColor
    hoverColor: lockRoot.hoverColor
    inputBg: lockRoot.inputBg
    rowBg: lockRoot.rowBg
    colors: lockRoot.colors

    playing: lockRoot.playing
    mediaTitle: lockRoot.currentTrack.title
    mediaArtist: lockRoot.currentTrack.artist
    mediaPos: lockRoot.posSeconds
    mediaDur: lockRoot.currentTrack.dur
    onMediaPrevRequested: lockRoot.mediaPrev()
    onMediaNextRequested: lockRoot.mediaNext()
    onMediaToggleRequested: lockRoot.mediaToggle()

    mode: lockRoot.mode
    users: lockRoot.mode === "lock" ? [lockRoot.realUser] : lockRoot.demoUsers
    selectedUser: lockRoot.selectedUser
    sessions: lockRoot.demoSessions
    selectedSession: lockRoot.selectedSession
    lockedAtText: lockRoot.lockedAtText
    pw: lockRoot.pw
    showPw: lockRoot.showPw
    authState: lockRoot.authState
    statusLine: lockRoot.statusLine
    capsOn: lockRoot.debugCapsOn
    armedPower: lockRoot.armedPower
    powerActions: lockRoot.powerActions
    fpOn: lockRoot.fpOn
    shakeSeq: lockRoot.shakeSeq

    onPwEdited: (text) => lockRoot.pw = text
    onSubmitRequested: lockRoot.submitPassword()
    onToggleShowRequested: lockRoot.showPw = !lockRoot.showPw
    onPickUserRequested: (index) => lockRoot.pickUser(index)
    onSessionStepRequested: (delta) => lockRoot.sessionStep(delta)
    onSwitchModeRequested: (m) => lockRoot.setMode(m)
    onPowerRequested: (action) => lockRoot.armOrFirePower(action)
    onDebugCapsToggleRequested: lockRoot.debugCapsOn = !lockRoot.debugCapsOn
}

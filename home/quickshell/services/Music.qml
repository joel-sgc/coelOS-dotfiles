pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Now playing, from Mpris: the player that's playing (else the first one), for
// the pill's music chip and the desktop's now-playing card. playerctld is
// skipped: it's a proxy that mirrors whichever real player is active.
//
// trackChanged(byUser) fires when the track changes while playing; byUser is
// true right after our own skip buttons, so the pill can skip its glance.
Singleton {
  id: mu

  readonly property var players: Mpris.players.values.filter(p => !/playerctld/i.test(p.dbusName || "") && !/playerctld/i.test(p.identity || ""))
  readonly property var player: {
    for (const p of players) if (p.playbackState === MprisPlaybackState.Playing) return p;
    return players.length ? players[0] : null;
  }
  readonly property bool playing: !!player && player.playbackState === MprisPlaybackState.Playing
  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string album: player ? (player.trackAlbum || "") : ""
  readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
  readonly property string source: player ? (player.identity || player.desktopEntry || "") : ""
  readonly property real length: player && player.lengthSupported ? player.length : 0
  property real position: 0
  readonly property real progress: length > 0 ? Math.min(1, position / length) : 0
  readonly property int volumePct: player && player.volumeSupported ? Math.round(player.volume * 100) : -1

  // Paused counts as "on" for 5 min (the desktop and the pill both drop it after).
  property real pausedAt: 0
  onPlayingChanged: pausedAt = playing ? 0 : Date.now()
  property real now: Date.now()
  readonly property bool active: !!player && title !== "" && (playing || (pausedAt > 0 && now - pausedAt < 5 * 60000))

  function fmt(s) {
    s = Math.max(0, Math.floor(s));
    return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
  }
  readonly property string line: title + (artist ? " — " + artist : "")

  // Mpris doesn't push position; ask for it every second while it moves.
  Timer {
    interval: 1000
    repeat: true
    running: !!mu.player
    onTriggered: {
      mu.now = Date.now();
      if (mu.player && mu.player.positionSupported) mu.position = mu.player.position;
    }
  }

  signal trackChanged(bool byUser)
  property real userActedAt: 0
  property string lastTitle: ""
  onTitleChanged: {
    if (title !== "" && lastTitle !== "" && title !== lastTitle && playing)
      trackChanged(Date.now() - userActedAt < 3000);
    lastTitle = title;
  }

  function toggle() { if (player && player.canTogglePlaying) player.togglePlaying(); }
  function next() { if (player && player.canGoNext) { userActedAt = Date.now(); player.next(); } }
  function previous() { if (player && player.canGoPrevious) { userActedAt = Date.now(); player.previous(); } }
}

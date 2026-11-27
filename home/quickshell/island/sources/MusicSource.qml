import QtQuick
import Quickshell
import "../../services"
import "../Parts.js" as P

// Music on the pill (Pill Board "Music · Mpris"), from services/Music:
//   playing        ambient: three bars that move with the music
//   paused         ambient: the bars freeze grey; gone after 5 min paused
//   track changed  glance 3 s (skipped when you skipped it yourself)
//   card           art, title, progress, controls
Scope {
  id: src
  property var engine
  readonly property var mu: Music

  readonly property var chips: !mu.active ? [] : [{
    id: "music", deskCard: "music", source: mu, prio: 70, card: cardComp,
    parts: [[P.eq(mu.playing ? P.C.gr : P.C.mu, mu.playing)]],
    label: mu.line, value: mu.fmt(mu.position), valueColor: mu.playing ? P.C.gr : P.C.mu
  }]

  Component { id: cardComp; MusicIslandCard {} }

  Connections {
    target: Music
    function onTrackChanged(byUser) {
      if (byUser) return;
      src.engine.glance({ id: "music-change", cardId: "music", source: Music, ms: 3000, accent: P.C.gr,
        parts: [P.icon("music-notes", P.C.gr, 14), P.text(Music.title, P.C.fg, 13, 360),
                P.muted(Music.artist, 13, 240), P.eq(P.C.gr, true)] });
    }
  }
}

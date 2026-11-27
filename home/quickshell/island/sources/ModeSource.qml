import QtQuick
import Quickshell
import "../../modes"
import "../Parts.js" as P

// The current mode (modes/Modes.qml) on the island:
//   a quiet ambient chip while it isn't Normal (least urgent: it shows only when
//   at most one other activity is up), and a 3 s glance whenever it changes.
Scope {
  id: src
  property var engine

  readonly property var inf: Modes.info[Modes.mode]

  readonly property var chips: Modes.mode === "normal" ? [] : [{
    id: "mode", source: src, prio: 95, card: null,
    parts: [[P.icon(inf.icon, inf.color, 12), P.text(inf.label, inf.color, 12)]],
    label: inf.label + (Modes.manual ? " (manual)" : ""), value: Modes.detail, valueColor: P.C.mu
  }]

  // Nothing to announce while the first readings settle after a (re)load.
  property bool ready: false
  Timer { interval: 4000; running: true; onTriggered: src.ready = true }

  property string shownMode: Modes.mode
  Connections {
    target: Modes
    function onModeChanged() {
      const was = src.shownMode;
      src.shownMode = Modes.mode;
      if (!src.ready || was === Modes.mode) return;
      const i = Modes.info[Modes.mode];
      const parts = [P.icon(i.icon, i.color, 14), P.text(i.label, i.color)];
      if (Modes.mode === "normal") parts.push(P.muted("· notifications back on"));
      else if (Modes.detail) parts.push(P.muted("· " + Modes.detail, 13, 420));
      if (Modes.dnd && Modes.mode !== "normal") parts.push(P.muted("· quiet"));
      src.engine.glance({ id: "mode", source: src, ms: 3000, accent: i.color, parts: parts, force: true });
    }
  }
}

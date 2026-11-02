pragma Singleton
import Quickshell
import QtQuick

// The "main" monitor, for things that live on one screen only (the desktop
// widgets): the built-in panel while it is on, otherwise the highest-
// resolution screen. Not Quickshell.screens[0] -- that list's order changes
// whenever outputs are reconfigured, which used to throw the widgets onto an
// external monitor.
//
// The screen is re-picked on every screen-list change, and once more after
// the list stops changing, so a reload that reshuffles outputs ends with the
// widgets back on the main monitor. While the list is momentarily empty the
// previous screen is kept.
Singleton {
  id: root

  property var screen: null

  function refresh() {
    const list = Quickshell.screens.slice();
    if (list.length === 0) return;
    const internal = list.find(s => /^(eDP|LVDS|DSI)/i.test(s.name));
    const best = internal || list.sort((a, b) => b.width * b.height - a.width * a.height)[0];
    if (root.screen !== best) root.screen = best;
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.refresh();
      settle.restart();
    }
  }
  Timer {
    id: settle
    interval: 500
    onTriggered: root.refresh()
  }
  Component.onCompleted: refresh()
}

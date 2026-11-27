pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// What you've done to the desktop's cards, kept in widgets.json (COEL_DATA_DIR
// overrides the folder): `min` {id: true} = minimized by you (always shelved),
// `pin` {id: {where: "hero"|"rail", size}} = holds its place through every mode.
// Both are replaced, never mutated, so bindings re-evaluate. Layout.js applies them.
Singleton {
  id: st

  // The card under the pointer / last clicked; it takes the keys (m, p, its own).
  property string focusId: ""
  property var min: ({})
  property var pin: ({})

  // The hand-off with the pill (Desktop Board "the travel"): per screen name, the
  // cards open on that desktop (hero/rail, not the shelf) with their rects in
  // screen coordinates. The pill drops those activities' chips while the screen's
  // workspace is empty, and flies them in and out.
  property var open: ({})
  function publish(screenName, rects) {
    const o = Object.assign({}, open);
    o[screenName] = rects;
    open = o;
  }
  // The morning greeting (desktop/Greeting.qml): 0 none, 1 lines in (cards
  // hidden), 2 cards fade and rise in (hero first, 40 ms apart), 3 shelf and mode
  // chip too. greetGlance(parts) asks the pill for the windows-open version.
  property int greetPhase: 0
  // The login intro (desktop/SessionIntro.qml) is on screen; the greeting waits.
  property bool introActive: false
  signal greetGlance(var parts)

  // A card's border flashes once: a chip landed on it, or a skipped glance.
  property var flashes: ({})
  function flash(id) {
    const f = Object.assign({}, flashes);
    f[id] = (f[id] || 0) + 1;
    flashes = f;
  }
  property bool dirReady: false
  property string lastSaved: ""
  readonly property string dataDir: Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")

  function save() {
    lastSaved = JSON.stringify({ min: min, pin: pin }, null, 2);
    file.setText(lastSaved);
  }
  // [–] on an open card / `m`: minimize (and unpin). [+] on a shelved card:
  // open it, pinned to the rail, since its mode would otherwise keep it shelved.
  function minimize(id) {
    const m = Object.assign({}, min), p = Object.assign({}, pin);
    m[id] = true;
    delete p[id];
    min = m; pin = p;
    save();
  }
  function open(id, size) {
    const m = Object.assign({}, min), p = Object.assign({}, pin);
    delete m[id];
    p[id] = { where: "rail", size: size };
    min = m; pin = p;
    save();
  }
  // `p`: pin where it is now (shelf -> rail), or unpin.
  function togglePin(id, slot, size, railSize) {
    const m = Object.assign({}, min), p = Object.assign({}, pin);
    if (p[id]) delete p[id];
    else p[id] = slot === "hero" ? { where: "hero", size: size } : { where: "rail", size: slot === "rail" ? size : railSize };
    delete m[id];
    min = m; pin = p;
    save();
  }

  Process {
    running: true
    command: ["mkdir", "-p", st.dataDir]
    onExited: st.dirReady = true
  }
  FileView {
    id: file
    path: st.dirReady ? st.dataDir + "/widgets.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      const t = text();
      if (t === st.lastSaved) return;
      try {
        const j = JSON.parse(t);
        st.min = j && typeof j.min === "object" && j.min ? j.min : {};
        st.pin = j && typeof j.pin === "object" && j.pin ? j.pin : {};
      } catch (e) {
        console.warn("desktop: widgets.json is not valid JSON, ignoring it:", e);
      }
    }
  }
}

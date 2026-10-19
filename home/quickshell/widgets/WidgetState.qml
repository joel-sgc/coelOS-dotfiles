pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Which desktop widgets are minimized, kept across restarts in
// widgets.json next to kanban.json (COEL_DATA_DIR overrides the folder, as
// in Kanban.qml). `min` is a plain object {id: true}; it is always replaced,
// never mutated, so bindings on isMin() re-evaluate.
Singleton {
  id: st

  // Which card the user last clicked; a card shows as focused only while it
  // is this one *and* its window has keyboard focus.
  property string focusId: ""
  property var min: ({})
  property bool dirReady: false
  property string lastSaved: ""
  readonly property string dataDir: Quickshell.env("COEL_DATA_DIR") || (Quickshell.env("HOME") + "/.local/share/coel")

  function isMin(id) { return !!min[id]; }
  function toggle(id) {
    const next = Object.assign({}, min);
    if (next[id]) delete next[id]; else next[id] = true;
    min = next;
    lastSaved = JSON.stringify({ min: next }, null, 2);
    file.setText(lastSaved);
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
    onFileChanged: reload()
    onLoaded: {
      const t = text();
      if (t === st.lastSaved) return;
      try {
        const j = JSON.parse(t);
        if (j && typeof j.min === "object" && j.min) st.min = j.min;
      } catch (e) {
        console.warn("widgets: widgets.json is not valid JSON, ignoring it:", e);
      }
    }
  }
}

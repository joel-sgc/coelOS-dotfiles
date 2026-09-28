import QtQuick
import Quickshell.Io

// ----- clipboard history (cliphist, replacing rofi's super+V picker) -----
// A real, always-browsable category (opened directly via super+V). Every
// real cliphist entry, no cap -- the list rendering (LauncherPanel.qml's
// ListView) is properly virtualized rather than a plain Column+Repeater.
//
// Only the entry list + the "copy on Enter" action live here. The *live
// preview* (real decoded content shown as you move selection, before
// you've chosen anything) stays in LauncherPanel.qml itself -- it's tied
// directly to that file's own `list`/`selIndex` state and drives a lot of
// preview-panel UI bindings there, so pulling it out here would trade a
// small win for a lot of forwarding-property indirection with no real
// separation of concerns to show for it.
Item {
  id: root

  property var entries: []
  function refresh() { proc.running = true; }

  Process {
    id: proc
    command: ["cliphist", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.entries = text.split("\n").filter(l => l.length > 0).map(line => {
          const tab = line.indexOf("\t");
          const preview = tab >= 0 ? line.slice(tab + 1) : line;
          // cliphist's own literal marker for image entries -- confirmed
          // against the real format string in the cliphist binary itself
          // ("[[ binary data %s %s %dx%d ]]"), not guessed.
          return { line, preview, isImage: preview.startsWith("[[ binary data") };
        });
      }
    }
  }

  function categoryItems() {
    return entries.map(entry => ({
      label: entry.isImage ? entry.preview : (entry.preview.length > 60 ? entry.preview.slice(0, 60) + "…" : entry.preview),
      sub: entry.isImage ? "image" : "text", icon: entry.isImage ? "image" : "clipboard", right: "",
      clipboardLine: entry.line, isImage: entry.isImage,
    }));
  }

  // cliphist list only shows a preview (truncated, and for images just the
  // marker above) -- the real content has to come back through `cliphist
  // decode`, which (like rofi's own dmenu pipeline) reads the exact list
  // line off stdin and looks the full value up by the id prefixed to it.
  property string pendingLine: ""
  function copyEntry(line) {
    pendingLine = line;
    // stdinEnabled gets set false below once the line's written, to signal
    // EOF -- since that's an imperative assignment it permanently
    // overrides the declarative `stdinEnabled: true` below (QML doesn't
    // revert to the original binding on its own), so it has to be put back
    // to true here before every run or the *second* copy in a launcher
    // session would start with no stdin pipe at all and silently write
    // nothing.
    copyProc.stdinEnabled = true;
    copyProc.running = true;
  }
  Process {
    id: copyProc
    command: ["sh", "-c", "cliphist decode | wl-copy"]
    stdinEnabled: true
    onStarted: { write(root.pendingLine + "\n"); stdinEnabled = false; }
  }
}

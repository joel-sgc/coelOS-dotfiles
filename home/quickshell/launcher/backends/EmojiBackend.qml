import QtQuick
import Quickshell.Io
import QtQuick.LocalStorage

// ----- emoji picker (replacing rofi-emoji / coel-emoji-picker) -----
// Was a one-time vendor of pkgs.rofi-emoji's bundled data -- discovered
// (2026-09-27) to be two full Unicode Emoji versions stale (missing all
// of 17.0/18.0: shaking face, cracking face, pickle, lighthouse,
// meteor, ...), since nothing was ever re-copying it as nixpkgs/upstream
// moved on. Now runs update-emoji-data.py, which fetches Unicode.org's
// own always-current emoji-test.txt (re-checked at most once a week,
// cached at $XDG_CACHE_HOME/quickshell-emoji-data.txt, falling back to
// the vendored emoji-data.txt on any network failure) -- see that
// script's own header for the full design. Loaded once per launcher
// lifetime (the `if (emoji.entries.length === 0)` gate in
// LauncherPanel.qml), not every panel open like AppsBackend -- even with
// the weekly refetch check, no reason to re-run this every time the
// launcher opens.
Item {
  id: root

  property var entries: []
  readonly property string updateScriptPath: Qt.resolvedUrl("../../scripts/update-emoji-data.py").toString().replace("file://", "")
  function refresh() { proc.running = true; }
  Process {
    id: proc
    command: ["python3", root.updateScriptPath]
    stdout: StdioCollector {
      onStreamFinished: {
        root.entries = text.split("\n").filter(l => l.length > 0).map(line => {
          const parts = line.split("\t");
          return { char: parts[0], category: parts[1] || "", name: parts[3] || "", keywords: parts[4] || "" };
        });
      }
    }
  }

  // ----- recently used emoji -----
  // Same physical SQLite database CalendarDropdown.qml's todos live in
  // (LocalStorage.openDatabaseSync is keyed by name+version, not by which
  // QML file opens it -- same name/version here really does mean the
  // same on-disk file) -- just a new table in it, per the user's own
  // instruction, rather than a second database file for one small table.
  property var db: null
  property var recentChars: [] // most-recent-first, capped to 5
  function openDb() {
    return LocalStorage.openDatabaseSync(
      "CoelOSCalendarTodos", "1.0",
      "Shared CoelOS quickshell local storage (calendar todos, emoji recency)", 1000000);
  }
  function ensureSchema() {
    db.transaction(function (tx) {
      tx.executeSql("CREATE TABLE IF NOT EXISTS emoji_recent (char TEXT PRIMARY KEY, used_at INTEGER NOT NULL)");
    });
  }
  function loadRecent() {
    const out = [];
    db.transaction(function (tx) {
      const rs = tx.executeSql("SELECT char FROM emoji_recent ORDER BY used_at DESC LIMIT 5");
      for (let i = 0; i < rs.rows.length; i++) out.push(rs.rows.item(i).char);
    });
    recentChars = out;
  }
  // Called from LauncherPanel.qml's runItem() the moment an emoji is
  // actually used (copied), not on mere selection -- "recently used"
  // should mean used, not just scrolled past.
  function recordUsed(char) {
    db.transaction(function (tx) {
      tx.executeSql("INSERT OR REPLACE INTO emoji_recent (char, used_at) VALUES (?, ?)", [char, Date.now()]);
    });
    loadRecent();
  }
  Component.onCompleted: {
    root.db = root.openDb();
    root.ensureSchema();
    root.loadRecent();
  }

  // Shared by LauncherPanel.qml's fuzzyList() normal path and the
  // emoji-only searchScope -- scored/sorted, not capped here (callers cap
  // as needed).
  function matches(q) {
    let out = [];
    entries.forEach(e => {
      const nl = e.name.toLowerCase();
      const hay = nl + " " + e.keywords.toLowerCase();
      if (!hay.includes(q)) return;
      const score = nl.startsWith(q) ? 3 : nl.split(/\s+/).some(w => w.startsWith(q)) ? 2 : e.keywords.toLowerCase().split(" | ").includes(q) ? 2 : 1;
      out.push({ label: e.char + "  " + e.name, sub: e.category, icon: "smiley", cat: "emoji", score, emojiChar: e.char });
    });
    out.sort((a, b) => b.score - a.score);
    return out;
  }
  // Plain (unscored) item shape for browsing rather than searching --
  // groupLabel drives LauncherPanel.qml's rows() header grouping, distinct
  // from the score-based "top hit" convention matches()/the calculator use.
  function browseItem(e, groupLabel) {
    return { label: e.char + "  " + e.name, sub: e.category, icon: "smiley", groupLabel, emojiChar: e.char };
  }
}

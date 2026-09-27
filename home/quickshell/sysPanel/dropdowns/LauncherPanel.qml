import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import QtQuick.LocalStorage

import "../Phosphor.js" as Phosphor
import "../Calc.js" as Calc

// ===== LAUNCHER PANEL =====
// Content for Launcher.qml's Spotlight overlay -- ported from the "Spotlight"
// block in "Quickshell Example/Quickshell Bar.dc.html" (search row, category
// chips, list+preview, about page, footer), with real content in place of
// that mock's generic Arch placeholders (see home/rofi.nix for what this is
// actually replacing).
//
// Phase 2 (this pass): items with a real effect now have one --
// Quickshell.execDetached for `command`, openPanelRequested() for `panel`,
// and real makoctl/systemd-inhibit backends for the two toggles that have
// one (see toggleDnd/toggleAwake below). Night light and charge limit stay
// message-only on purpose: no compositor night-light tool is installed
// (checked: no hyprsunset/gammastep/wlsunset), and PowerDropdown.qml's own
// header comment already found this hardware has no real charge-limit
// sysfs knob -- showing a fake toggle for either would be worse than an
// honest "not available" message.
//
// Also new this pass: application search, replacing rofi's `-show drun`
// (see the "launch" category, which no longer has its own "Programs" item
// pointing at rofi). Spotlight-style, not rofi-style -- installedApps only
// ever enters `list` while hasQuery is true, so nothing app-related shows
// until you actually type, same as the rest of this file's search-only
// entries. list-apps.py parses real .desktop files (NoDisplay/Hidden
// filtered, Exec field codes stripped) rather than shelling back out to
// rofi/xdg tooling.
//
// The preview panel takes either an icon glyph or an image (`previewImage`
// on each row) -- app search results are the first real use of that (via
// Quickshell.iconPath resolving each entry's real Icon= value), and it's
// also what the clipboard/emoji picker planned for this launcher will use
// later for real thumbnails.
Item {
  id: panelRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property color bgColor: "#282c34"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  property bool panelOpen: false
  // Set (via Launcher.qml/shell.qml) right before panelOpen flips true when
  // opened through openCategoryRequested (super+V) -- jumps straight to
  // that category instead of leaving catIndex wherever it last was. Empty
  // string (the plain-toggle case) leaves catIndex untouched.
  property string requestedCategory: ""
  // A live-bound restriction on what fuzzyList() searches at all (not a
  // one-time jump like requestedCategory above -- stays in effect for as
  // long as the launcher's open this way). "" = normal search across
  // everything; "emoji" (super+., openEmoji) = emoji results only, no
  // categories/apps/clipboard/calculator. General mechanism, one concrete
  // value wired up so far -- see fuzzyList()'s early-return branch.
  property string searchScope: ""

  signal closeRequested()
  signal openPanelRequested(string name)

  onPanelOpenChanged: if (panelOpen) {
    query = "";
    view = "";
    selIndex = 0;
    catIndex = 0;
    msg = "";
    armedId = "";
    if (requestedCategory !== "") {
      const idx = categories.findIndex(c => c.id === requestedCategory);
      if (idx >= 0) catIndex = idx;
    }
    searchInput.forceActiveFocus();
    refreshDnd();
    refreshApps();
    refreshClipboard();
    if (emojiEntries.length === 0) refreshEmoji();
  }

  // ----- category/item data -----
  // Real commands/scripts from home/rofi.nix (coel-main-menu and its
  // sub-menus) and PowerDropdown.qml's session actions, not the mock's
  // Arch/fuzzel/kitty placeholders -- see the header comment on why none
  // of these actually run yet regardless.
  // A function, not a static literal -- the toggles category's "right"
  // badges reflect real state (dndOn/awakeOn), so this has to re-run
  // whenever that changes. Calling it from a property binding (below)
  // still gives normal reactive tracking: QML follows property reads
  // that happen *inside* a called function just as it would inline.
  function buildCategories() {
    return [
      { id: "launch", label: "launch", icon: "rocket-launch", items: [
        { label: "Terminal", sub: "ghostty", icon: "terminal-window", right: "", command: ["ghostty"] },
        { label: "Browser", sub: "zen", icon: "globe", right: "", command: ["zen"] },
        { label: "Editor", sub: "$EDITOR", icon: "code", right: "", command: ["ghostty", "-e", "fresh"] },
        { label: "Files", sub: "dolphin", icon: "folder", right: "", command: ["dolphin"] },
      ] },
      { id: "toggles", label: "toggles", icon: "toggle-right", items: [
        { id: "dnd", label: "Do not disturb", sub: "silence notifications", icon: "bell-slash", right: dndOn ? "[on]" : "[off]", rightColor: dndOn ? colors[3] : mutedColor },
        { id: "nightlight", label: "Night light", sub: "no compositor tool installed", icon: "moon-stars", right: "n/a", rightColor: mutedColor },
        { id: "awake", label: "Keep awake", sub: "inhibit idle & sleep", icon: "coffee", right: awakeOn ? "[on]" : "[off]", rightColor: awakeOn ? colors[3] : mutedColor },
        { id: "chargelimit", label: "Charge limit", sub: "no charge-limit control on this hardware", icon: "battery-plus", right: "n/a", rightColor: mutedColor },
      ] },
      { id: "capture", label: "capture", icon: "camera", items: [
        { label: "Screenshot", sub: "region → clipboard", icon: "selection", right: "print", command: ["coel-screenshot"] },
        { label: "Screen record", sub: "region → file", icon: "record", right: "", command: ["coel-screenrecord"] },
        { label: "Color picker", sub: "hex → clipboard", icon: "eyedropper", right: "", command: ["hyprpicker", "-a"] },
      ] },
      // Real browsable category (not search-only like emoji/apps) --
      // clipboardCategoryItems() maps every real cliphist entry, capped
      // only by cliphist's own history size, not by us. The list below
      // is a virtualized ListView specifically so this doesn't mean
      // instantiating hundreds of QML rows at once when this chip is
      // selected with no search query.
      { id: "clipboard", label: "clipboard", icon: "clipboard-text", items: clipboardCategoryItems() },
      { id: "math", label: "math", icon: "function", items: [
        ["sqrt16", "square root"], ["root(3)(27)", "nth root"], ["log(2)(1024)", "log base 2"],
        ["5!", "factorial"], ["ncr(10, 3)", "combinations"], ["120 + 15%", "percent of"],
      ].map(([ex, d]) => ({ label: ex, sub: d, icon: "function", right: "", fill: true })) },
      { id: "system", label: "system", icon: "gear-six", items: [
        { label: "About this system", sub: "", icon: "info", right: "›", rightColor: "#5c6370", view: "about" },
        { label: "Rebuild", sub: "nixos-rebuild switch", icon: "arrow-counter-clockwise", right: "", command: ["ghostty", "--class=com.joelsgc.floating", "-e", "coel-rebuild"] },
        { label: "Update", sub: "+ upgrade flake inputs", icon: "arrows-clockwise", right: "", command: ["ghostty", "--class=com.joelsgc.floating", "-e", "coel-update"] },
        { label: "Lock", sub: "", icon: "lock", right: "super+l", command: ["hyprlock"] },
        { id: "suspend", label: "Suspend", sub: "", icon: "moon", right: "", danger: true, command: ["systemctl", "suspend"] },
        { id: "reboot", label: "Reboot", sub: "", icon: "arrow-clockwise", right: "", danger: true, command: ["systemctl", "reboot"] },
        { id: "poweroff", label: "Shut down", sub: "", icon: "power", right: "", danger: true, command: ["systemctl", "poweroff"] },
      ] },
    ];
  }
  readonly property var categories: buildCategories()

  property string query: ""
  property int catIndex: 0
  property int selIndex: 0
  property string view: "" // "" | "about"
  property string msg: ""
  property bool msgIsArmed: false
  property string armedId: ""
  // Last *global* (screen) cursor position seen by a row's hover handler --
  // see the itemDelegate's onPositionChanged below. listFlick.moving alone
  // didn't fix the scroll-drags-selection bug: Qt Quick treats mouse-wheel
  // scrolling on a Flickable as a direct contentY change, not a drag/flick
  // gesture, so `moving` never actually goes true for it. Comparing global
  // cursor position instead catches the real cause directly -- a row
  // sliding under a *stationary* cursor during scroll still changes that
  // row's local mouse coordinates (since the row itself moved), firing
  // onPositionChanged, even though the cursor never actually moved on
  // screen. Global position is unaffected by the row moving underneath it.
  property point lastHoverGlobalPos: Qt.point(-100000, -100000)
  // Last real calculator result, fed back in as `ans` for the next
  // expression -- Calc.js takes it as a plain argument (no `this.state` to
  // close over the way the mock's calcEval() does it).
  property real ansValue: 0

  // ----- real toggle backends -----
  // dndOn is re-read from mako itself after every toggle (never assumed)
  // -- same "don't optimistically update, wait for the next real read"
  // rule SystemDropdown.qml's kill action follows. awakeOn doesn't need
  // that: it's not external state anything else can change, just whether
  // *our own* systemd-inhibit child process is currently alive, which we
  // fully control.
  property bool dndOn: false
  property bool awakeOn: false

  function refreshDnd() { dndProc.running = true; }
  Process {
    id: dndProc
    command: ["makoctl", "mode"]
    stdout: StdioCollector {
      onStreamFinished: panelRoot.dndOn = text.split("\n").some(l => l.trim() === "dnd")
    }
  }
  Process {
    id: dndToggleProc
    command: ["makoctl", "mode", "-t", "dnd"]
    onExited: panelRoot.refreshDnd()
  }
  function toggleDnd() {
    dndToggleProc.running = true;
    msg = "toggling do not disturb…";
  }

  // Held open the whole time awakeOn is true; `running: false` sends it
  // SIGTERM, which releases the inhibitor immediately (systemd-inhibit's
  // own lock lasts exactly as long as the process holding it does).
  Process {
    id: awakeProc
    command: ["systemd-inhibit", "--what=idle:sleep", "--who=CoelOS launcher", "--why=keep awake toggled from launcher", "sleep", "infinity"]
  }
  function toggleAwake() {
    awakeOn = !awakeOn;
    awakeProc.running = awakeOn;
    msg = "keep awake " + (awakeOn ? "on" : "off");
  }

  // ----- app search (rofi -show drun replacement) -----
  property var installedApps: []
  readonly property string appsScriptPath: Qt.resolvedUrl("../../scripts/list-apps.py").toString().replace("file://", "")
  function refreshApps() { appsProc.running = true; }
  Process {
    id: appsProc
    command: ["python3", panelRoot.appsScriptPath]
    stdout: StdioCollector {
      onStreamFinished: {
        try { panelRoot.installedApps = JSON.parse(text); } catch (e) { panelRoot.installedApps = []; }
      }
    }
  }

  // ----- clipboard history (cliphist, replacing rofi's super+V picker) -----
  // A real, always-browsable category now (not search-only like apps/emoji
  // below) -- opened directly via super+V. Every real cliphist entry, no
  // cap, since the list rendering (see the ListView further down) is
  // properly virtualized rather than a plain Column+Repeater.
  property var clipboardEntries: []
  function refreshClipboard() { clipboardProc.running = true; }
  Process {
    id: clipboardProc
    command: ["cliphist", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        panelRoot.clipboardEntries = text.split("\n").filter(l => l.length > 0).map(line => {
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
  function clipboardCategoryItems() {
    return clipboardEntries.map(entry => ({
      label: entry.isImage ? entry.preview : (entry.preview.length > 60 ? entry.preview.slice(0, 60) + "…" : entry.preview),
      sub: entry.isImage ? "image" : "text", icon: entry.isImage ? "image" : "clipboard", right: "",
      clipboardLine: entry.line, isImage: entry.isImage,
    }));
  }
  // cliphist list only shows a preview (truncated, and for images just the
  // marker above) -- the real content has to come back through `cliphist
  // decode`, which (like rofi's own dmenu pipeline) reads the exact list
  // line off stdin and looks the full value up by the id prefixed to it.
  // Used two ways: copyClipboardEntry() (piped straight to wl-copy, real
  // content never touches a shell string) for Enter/click, and the two
  // preview-decode Processes below for showing real content live as you
  // move selection, before you've actually chosen anything.
  property string pendingClipboardLine: ""
  function copyClipboardEntry(line) {
    pendingClipboardLine = line;
    // stdinEnabled gets set false below once the line's written, to signal
    // EOF -- since that's an imperative assignment it permanently
    // overrides the declarative `stdinEnabled: true` below (QML doesn't
    // revert to the original binding on its own), so it has to be put back
    // to true here before every run or the *second* copy in a launcher
    // session would start with no stdin pipe at all and silently write
    // nothing.
    clipboardCopyProc.stdinEnabled = true;
    clipboardCopyProc.running = true;
  }
  Process {
    id: clipboardCopyProc
    command: ["sh", "-c", "cliphist decode | wl-copy"]
    stdinEnabled: true
    onStarted: { write(panelRoot.pendingClipboardLine + "\n"); stdinEnabled = false; }
  }

  // ----- clipboard live preview (real decoded content, not the mangled/
  // truncated list preview -- respects the original text's whitespace and
  // renders real images) -----
  // The two decode Processes are deliberately serialized: never start a
  // new decode while one's still in flight for a previous selection.
  // Rapid arrow-key movement would otherwise mean two `cliphist decode`
  // calls racing to write the *same* temp image file, which could
  // interleave into a corrupted image. Instead, a process that finishes
  // and finds the selection has already moved on (`forLine` no longer
  // matches the live selection) just re-checks and kicks off a fresh
  // decode for wherever the selection actually is now.
  property string clipPreviewLine: ""
  property bool clipPreviewIsImage: false
  property bool clipPreviewLoading: false
  property string clipPreviewText: ""
  property string clipPreviewImagePath: ""
  readonly property string clipPreviewImageFile: "/tmp/quickshell-clip-preview.bin"
  readonly property var currentPreviewItem: list.length > 0 ? list[Math.min(selIndex, list.length - 1)] : null
  onCurrentPreviewItemChanged: updateClipboardPreview(false)

  function updateClipboardPreview(force) {
    const cur = currentPreviewItem;
    if (!cur || cur.clipboardLine === undefined) {
      clipPreviewLine = "";
      clipPreviewText = "";
      clipPreviewImagePath = "";
      clipPreviewIsImage = false;
      clipPreviewLoading = false;
      return;
    }
    if (!force && cur.clipboardLine === clipPreviewLine) return;
    clipPreviewLine = cur.clipboardLine;
    clipPreviewIsImage = !!cur.isImage;
    clipPreviewLoading = true;
    if (cur.isImage) {
      if (clipImageDecodeProc.running) return;
      clipImageDecodeProc.forLine = cur.clipboardLine;
      // Same reset-before-run requirement as copyClipboardEntry() above --
      // this is exactly the bug that made the preview only ever work for
      // the *first* selection: stdinEnabled was left false from the
      // previous run's onStarted, so every run after the first wrote to a
      // closed stdin and cliphist decode never saw its input.
      clipImageDecodeProc.stdinEnabled = true;
      clipImageDecodeProc.running = true;
    } else {
      if (clipTextDecodeProc.running) return;
      clipTextDecodeProc.forLine = cur.clipboardLine;
      clipTextDecodeProc.stdinEnabled = true;
      clipTextDecodeProc.running = true;
    }
  }
  Process {
    id: clipTextDecodeProc
    property string forLine: ""
    command: ["sh", "-c", "cliphist decode"]
    stdinEnabled: true
    onStarted: { write(forLine + "\n"); stdinEnabled = false; }
    stdout: StdioCollector {
      onStreamFinished: {
        if (clipTextDecodeProc.forLine === panelRoot.clipPreviewLine) {
          panelRoot.clipPreviewText = text;
          panelRoot.clipPreviewLoading = false;
        } else {
          panelRoot.updateClipboardPreview(true);
        }
      }
    }
  }
  Process {
    id: clipImageDecodeProc
    property string forLine: ""
    command: ["sh", "-c", "cliphist decode > " + panelRoot.clipPreviewImageFile]
    stdinEnabled: true
    onStarted: { write(forLine + "\n"); stdinEnabled = false; }
    onExited: {
      if (clipImageDecodeProc.forLine === panelRoot.clipPreviewLine) {
        panelRoot.clipPreviewImagePath = "file://" + panelRoot.clipPreviewImageFile + "?t=" + Date.now();
        panelRoot.clipPreviewLoading = false;
      } else {
        panelRoot.updateClipboardPreview(true);
      }
    }
  }

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
  // lifetime (the `if (emojiEntries.length === 0)` gate below), not every
  // panel open like the app list -- even with the weekly refetch check,
  // no reason to re-run this every time the launcher opens.
  // Still search-only when reached from the *main* launcher (no chip --
  // matches/emojiMatches() below stays capped at 20 for the same
  // render-count reason as clipboard/apps). The dedicated emoji-only
  // scope (super+., searchScope==="emoji") is different: browsable by
  // default with no query at all, see fuzzyList()'s searchScope branch --
  // safe now that the ListView is properly virtualized (the same fix the
  // clipboard tab needed for the same reason).
  property var emojiEntries: []
  readonly property string emojiUpdateScriptPath: Qt.resolvedUrl("../../scripts/update-emoji-data.py").toString().replace("file://", "")
  function refreshEmoji() { emojiProc.running = true; }
  Process {
    id: emojiProc
    command: ["python3", panelRoot.emojiUpdateScriptPath]
    stdout: StdioCollector {
      onStreamFinished: {
        panelRoot.emojiEntries = text.split("\n").filter(l => l.length > 0).map(line => {
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
  property var emojiDb: null
  property var recentEmojiChars: [] // most-recent-first, capped to 5
  function openEmojiDb() {
    return LocalStorage.openDatabaseSync(
      "CoelOSCalendarTodos", "1.0",
      "Shared CoelOS quickshell local storage (calendar todos, emoji recency)", 1000000);
  }
  function emojiDbEnsureSchema() {
    emojiDb.transaction(function (tx) {
      tx.executeSql("CREATE TABLE IF NOT EXISTS emoji_recent (char TEXT PRIMARY KEY, used_at INTEGER NOT NULL)");
    });
  }
  function loadRecentEmoji() {
    const out = [];
    emojiDb.transaction(function (tx) {
      const rs = tx.executeSql("SELECT char FROM emoji_recent ORDER BY used_at DESC LIMIT 5");
      for (let i = 0; i < rs.rows.length; i++) out.push(rs.rows.item(i).char);
    });
    recentEmojiChars = out;
  }
  // Called from runItem() the moment an emoji is actually used (copied),
  // not on mere selection -- "recently used" should mean used, not just
  // scrolled past.
  function recordEmojiUsed(char) {
    emojiDb.transaction(function (tx) {
      tx.executeSql("INSERT OR REPLACE INTO emoji_recent (char, used_at) VALUES (?, ?)", [char, Date.now()]);
    });
    loadRecentEmoji();
  }

  // Shared by fuzzyList()'s normal path and the emoji-only searchScope
  // below -- scored/sorted, not capped here (callers cap as needed).
  function emojiMatches(q) {
    let matches = [];
    emojiEntries.forEach(e => {
      const nl = e.name.toLowerCase();
      const hay = nl + " " + e.keywords.toLowerCase();
      if (!hay.includes(q)) return;
      const score = nl.startsWith(q) ? 3 : nl.split(/\s+/).some(w => w.startsWith(q)) ? 2 : e.keywords.toLowerCase().split(" | ").includes(q) ? 2 : 1;
      matches.push({ label: e.char + "  " + e.name, sub: e.category, icon: "smiley", cat: "emoji", score, emojiChar: e.char });
    });
    matches.sort((a, b) => b.score - a.score);
    return matches;
  }
  // Plain (unscored) item shape for browsing rather than searching --
  // groupLabel drives the rows() header grouping below, distinct from the
  // score-based "top hit" convention emojiMatches()/the calculator use.
  function emojiBrowseItem(e, groupLabel) {
    return { label: e.char + "  " + e.name, sub: e.category, icon: "smiley", groupLabel, emojiChar: e.char };
  }

  function fuzzyList() {
    const raw = query.trim(), q = raw.toLowerCase();
    // super+. (openEmoji) restricts the whole launcher to emoji-only
    // search -- excludes categories, apps, clipboard, calculator; just
    // emoji, per the user's own "exclude categories on command" request.
    if (searchScope === "emoji") {
      if (!q) {
        // Browsable by default here (unlike emoji reached from the main
        // launcher, which stays search-only) -- safe now that the list is
        // a real virtualized ListView, same as the clipboard tab. Recently
        // *used* (copied, not just scrolled past -- see recordEmojiUsed())
        // emoji are pulled to their own group up top and not duplicated
        // further down; everything else keeps Unicode's own curated
        // group/subgroup order from emoji-test.txt.
        if (emojiEntries.length === 0) return [];
        const recentSet = new Set(recentEmojiChars);
        const recentItems = recentEmojiChars
          .map(ch => emojiEntries.find(e => e.char === ch))
          .filter(e => !!e)
          .map(e => emojiBrowseItem(e, "recently used"));
        const restItems = emojiEntries
          .filter(e => !recentSet.has(e.char))
          .map(e => emojiBrowseItem(e, e.category));
        return recentItems.concat(restItems);
      }
      let matches = emojiMatches(q).slice(0, 50);
      if (matches.length > 0) {
        let bi = 0;
        matches.forEach((x, i) => { if (x.score > matches[bi].score) bi = i; });
        matches = [Object.assign({}, matches[bi], { top: true })].concat(matches.filter((_, i) => i !== bi));
      }
      return matches;
    }
    if (!q) {
      const c = categories[Math.min(catIndex, categories.length - 1)];
      return c.items.map(it => Object.assign({}, it, { cat: c.label }));
    }
    let list = [];
    categories.forEach(c => c.items.forEach(it => {
      const l = it.label.toLowerCase();
      const hay = (l + " " + (it.sub || "") + " " + c.label).toLowerCase();
      if (!hay.includes(q)) return;
      const score = l.startsWith(q) ? 3 : l.split(/[\s-]+/).some(w => w.startsWith(q)) ? 2 : l.includes(q) ? 1 : 0;
      list.push(Object.assign({}, it, { cat: c.label, score }));
    }));
    // Spotlight-style, not rofi-style: installed apps only ever show up
    // here, inside a real search -- there's no "applications" chip to
    // browse, matching "no results until typed" rather than dumping
    // every installed app by default.
    installedApps.forEach(app => {
      // Plasma's own "Emoji Selector" (plasma-emojier) is a real installed
      // app -- list-apps.py is right to surface it -- but it's redundant
      // now that emoji search below is native to the launcher, and having
      // both show up for the same query is just confusing. Filtered here,
      // not in list-apps.py, since "real vs redundant" is a launcher UX
      // call, not something the app scanner should be opinionated about.
      if (app.argv && app.argv[0] === "plasma-emojier") return;
      const l = app.name.toLowerCase();
      const hay = (l + " " + (app.comment || "")).toLowerCase();
      if (!hay.includes(q)) return;
      const score = l.startsWith(q) ? 3 : l.split(/[\s-]+/).some(w => w.startsWith(q)) ? 2 : l.includes(q) ? 1 : 0;
      list.push({
        label: app.name, sub: app.comment, icon: "squares-four",
        previewImage: app.icon ? Quickshell.iconPath(app.icon, "") : "",
        cat: "applications", score,
        command: app.terminal ? ["ghostty", "-e"].concat(app.argv) : app.argv,
      });
    });
    // Clipboard search is handled above for free -- it's a real category
    // now (categories.forEach already covers it), unlike emoji below,
    // which stays a separate, capped, search-only source (5042 entries is
    // too many to ever browse as a static category list; clipboard's own
    // up-to-hundreds is fine now that the list rendering is virtualized).
    const emojiMatchList = emojiMatches(q);
    list = list.concat(emojiMatchList.slice(0, 20));
    if (list.length > 0) {
      let bi = 0;
      list.forEach((x, i) => { if (x.score > list[bi].score) bi = i; });
      list = [Object.assign({}, list[bi], { top: true })].concat(list.filter((_, i) => i !== bi));
    }
    // A valid calculator expression always wins the top slot, same as the
    // mock's menuList() -- e.g. typing "5!" shouldn't have to compete with
    // a fuzzy-matched "System" entry for the top-hit spot.
    const c = Calc.evaluate(raw, ansValue);
    if (c) {
      list = [{
        label: "= " + c.display, sub: c.pretty, icon: "calculator", cat: "calculator", calc: c, top: true,
      }].concat(list.map(x => Object.assign({}, x, { top: false })));
    }
    return list;
  }
  readonly property var list: fuzzyList()
  readonly property bool hasQuery: query.trim().length > 0
  readonly property bool aboutView: view === "about"

  // Deliberately does NOT embed isSel per-row (used to: `isSel: i ===
  // selIndex`) -- that made this whole array, and therefore the ListView's
  // model, get rebuilt into a brand-new array reference on every selIndex
  // change (e.g. plain mouse hover). Reassigning a ListView's model to a
  // new array identity resets its scroll position, which made the
  // clipboard tab (the first real ListView-backed browsable list) appear
  // to refuse to scroll -- any hover during a scroll gesture snapped it
  // back. Each delegate now reads panelRoot.selIndex directly instead
  // (see itemDelegate's own `isSel` below), so rows only changes when
  // `list` itself does (new search, category switch, refreshed data).
  // Grouped/headered whenever there's a query, OR a scope restriction is
  // active (e.g. emoji-only's browse-all-by-default view, which has no
  // query but still wants "recently used" / per-category headers) --
  // groupLabel lets a caller override the header text away from the
  // plain `cat` field (used for "recently used" vs. real category names)
  // without disturbing the "top hit" convention search results still use.
  readonly property var rows: {
    const out = [];
    let prevGroup = null;
    const grouped = hasQuery || panelRoot.searchScope !== "";
    list.forEach((it, i) => {
      if (grouped) {
        if (it.top) { out.push({ isHeader: true, header: "top hit" }); }
        else {
          const g = it.groupLabel || it.cat;
          if (g !== prevGroup) { out.push({ isHeader: true, header: g }); prevGroup = g; }
        }
      }
      out.push({ isItem: true, idx: i, item: it });
    });
    return out;
  }

  function currentItem() {
    if (list.length === 0) return null;
    return list[Math.min(selIndex, list.length - 1)];
  }
  // ListView has no idea a plain `selIndex` integer even exists -- there's
  // no ListView.currentIndex binding anywhere here, selection is tracked
  // entirely by hand (see the `rows`/isSel comments above for why). That
  // means it never auto-scrolls to follow keyboard navigation on its own;
  // this has to be done explicitly. `rows` interleaves header rows when
  // searching, so selIndex (an index into `list`) isn't always the same
  // as the row index in `rows`/the ListView -- found by matching `idx`.
  // positionViewAtIndex jumps the view instantly, unlike a gradual wheel
  // scroll -- with reuseItems:true that can mean a recycled delegate gets
  // rebound to a completely different row right under a mouse that never
  // moved, and (apparently, empirically -- the mapToGlobal check in the
  // delegate's onPositionChanged doesn't catch every case here the way it
  // does for wheel-scrolling) that can still hijack keyboard-driven
  // selection. Rather than chase the exact internal Qt Quick event path
  // for this one, hover is just flatly suppressed for a short window
  // around any programmatic scroll -- see hoverSuppressTimer/
  // suppressHoverSelect below and in the delegate.
  property bool suppressHoverSelect: false
  Timer {
    id: hoverSuppressTimer
    interval: 250
    onTriggered: panelRoot.suppressHoverSelect = false
  }
  function scrollSelectedIntoView() {
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].isItem && rows[i].idx === selIndex) {
        suppressHoverSelect = true;
        hoverSuppressTimer.restart();
        listFlick.positionViewAtIndex(i, ListView.Contain);
        return;
      }
    }
  }
  function moveSel(delta) {
    if (list.length === 0) return;
    selIndex = Math.max(0, Math.min(list.length - 1, selIndex + delta));
    msg = "";
    scrollSelectedIntoView();
  }
  function moveCat(delta) {
    catIndex = (catIndex + delta + categories.length) % categories.length;
    selIndex = 0;
    msg = "";
    scrollSelectedIntoView();
  }
  function pickCat(i) {
    catIndex = i;
    selIndex = 0;
    msg = "";
    searchInput.forceActiveFocus();
    scrollSelectedIntoView();
  }
  function runItem(it) {
    if (!it) return;
    if (it.clipboardLine !== undefined) {
      copyClipboardEntry(it.clipboardLine);
      msg = "→ copied from clipboard history";
      closeRequested();
      return;
    }
    if (it.emojiChar) {
      Quickshell.execDetached(["wl-copy", it.emojiChar]);
      recordEmojiUsed(it.emojiChar);
      msg = "→ copied " + it.emojiChar;
      closeRequested();
      return;
    }
    if (it.calc) {
      const c = it.calc;
      if (c.ok) {
        Quickshell.execDetached(["wl-copy", c.raw]);
        ansValue = c.value;
        msg = "copied " + c.display;
      } else {
        msg = c.reason;
      }
      armedId = "";
      return;
    }
    if (it.fill) {
      query = it.label;
      selIndex = 0;
      searchInput.forceActiveFocus();
      return;
    }
    if (it.view) {
      view = it.view;
      msg = "";
      return;
    }
    if (it.id === "dnd") { toggleDnd(); return; }
    if (it.id === "awake") { toggleAwake(); return; }
    if (it.id === "nightlight") { msg = "no compositor night-light tool installed (hyprsunset/gammastep/wlsunset)"; return; }
    if (it.id === "chargelimit") { msg = "no charge-limit control on this hardware (checked: no sysfs threshold, no ec tool)"; return; }
    if (it.danger) {
      const id = it.id || it.label;
      if (armedId !== id) {
        armedId = id;
        msg = "press ⏎ again to " + it.label.toLowerCase();
        return;
      }
      armedId = "";
    }
    if (it.panel) {
      openPanelRequested(it.panel);
      msg = "→ opens " + it.label.toLowerCase() + " panel";
      closeRequested();
      return;
    }
    if (it.command) {
      Quickshell.execDetached(it.command);
      msg = "→ " + it.command.join(" ");
      closeRequested();
      return;
    }
    msg = "→ " + it.label.toLowerCase();
  }

  focus: true
  Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Escape) {
      event.accepted = true;
      if (aboutView) { view = ""; return; }
      if (hasQuery) { query = ""; selIndex = 0; return; }
      closeRequested();
      return;
    }
    if (aboutView) {
      if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Left || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        event.accepted = true;
        view = "";
      }
      return;
    }
    switch (event.key) {
      case Qt.Key_Down:
        event.accepted = true; moveSel(1); break;
      case Qt.Key_Up:
        event.accepted = true; moveSel(-1); break;
      case Qt.Key_Tab:
        if (!hasQuery) { event.accepted = true; moveCat(1); }
        break;
      case Qt.Key_Backtab:
        if (!hasQuery) { event.accepted = true; moveCat(-1); }
        break;
      case Qt.Key_Right:
        if (!hasQuery) { event.accepted = true; moveCat(1); }
        break;
      case Qt.Key_Left:
        if (!hasQuery) { event.accepted = true; moveCat(-1); }
        break;
      case Qt.Key_Return:
      case Qt.Key_Enter:
        event.accepted = true;
        runItem(currentItem());
        break;
    }
  }

  implicitWidth: 720
  implicitHeight: card.implicitHeight

  Rectangle {
    id: card
    width: parent.width
    implicitHeight: column.implicitHeight
    color: panelRoot.bgColor
    radius: 14
    border.width: 1
    border.color: panelRoot.hoverColor
    clip: true

    // Eats clicks anywhere on the card so they don't fall through to
    // Launcher.qml's full-screen backdrop MouseArea underneath (which
    // would otherwise treat "click on blank card padding" the same as
    // "click outside the card" and close this).
    MouseArea { anchors.fill: parent }

    Column {
      id: column
      width: parent.width
      spacing: 0

      // ----- search row -----
      RowLayout {
        width: parent.width
        spacing: 12
        Layout.margins: 0
        anchors.margins: 0
        Text {
          Layout.leftMargin: 18
          text: Phosphor.icon("magnifying-glass")
          font.family: "Phosphor"
          font.pixelSize: 20
          color: panelRoot.colors[0]
        }
        TextInput {
          id: searchInput
          Layout.fillWidth: true
          Layout.topMargin: 14
          Layout.bottomMargin: 14
          text: panelRoot.query
          color: panelRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 18
          selectByMouse: true
          onTextEdited: { panelRoot.query = text; panelRoot.selIndex = 0; panelRoot.armedId = ""; panelRoot.view = ""; }
          Keys.forwardTo: [panelRoot]

          Text {
            visible: searchInput.text.length === 0
            anchors.verticalCenter: parent.verticalCenter
            text: panelRoot.searchScope === "emoji" ? "search emoji — grinning, heart, fire…" : "search, or calculate — sqrt16, log(2)(8), 5!"
            color: panelRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 18
          }
        }
        Text {
          Layout.rightMargin: 18
          text: panelRoot.hasQuery ? (panelRoot.list.length + " result" + (panelRoot.list.length === 1 ? "" : "s")) : "ctrl k"
          color: panelRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }
      }

      // ----- category chips -----
      // Hidden entirely while a searchScope restriction is active (e.g.
      // emoji-only via super+.) -- there's nothing to browse by category
      // in that mode, categories aren't even consulted by fuzzyList().
      Flow {
        visible: !panelRoot.hasQuery && !panelRoot.aboutView && panelRoot.searchScope === ""
        x: 14
        width: parent.width - 28
        spacing: 4
        Repeater {
          model: panelRoot.categories
          delegate: Rectangle {
            id: chip
            required property var modelData
            required property int index
            readonly property bool active: index === panelRoot.catIndex
            implicitWidth: chipRow.implicitWidth + 20
            implicitHeight: 22
            radius: 6
            color: active ? "#2f343e" : (chipMouse.containsMouse ? "#353b45" : "transparent")
            Row {
              id: chipRow
              anchors.centerIn: parent
              spacing: 6
              Text {
                text: Phosphor.icon(chip.modelData.icon)
                font.family: "Phosphor"
                font.pixelSize: 13
                color: chip.active ? panelRoot.colors[0] : panelRoot.mutedColor
              }
              Text {
                text: chip.modelData.label
                font.family: "JetBrains Mono"
                font.pixelSize: 13
                color: chip.active ? panelRoot.fgColor : "#7f848e"
              }
            }
            MouseArea {
              id: chipMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: panelRoot.pickCat(chip.index)
            }
          }
        }
      }

      Item { visible: !panelRoot.hasQuery && !panelRoot.aboutView && panelRoot.searchScope === ""; width: 1; height: 10 }

      Rectangle { width: parent.width; height: 1; color: panelRoot.hoverColor }

      // ----- list + preview -----
      Item {
        visible: !panelRoot.aboutView
        width: parent.width
        height: visible ? 336 : 0

        // A real ListView, not a Flickable+Column+Repeater -- the clipboard
        // category can now hold hundreds of real entries with no cap, and
        // ListView only ever instantiates delegates near the visible
        // viewport (reuseItems recycles them further), unlike a plain
        // Repeater which would build every row up front regardless of
        // scroll position.
        ListView {
          id: listFlick
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: parent.width - 240
          leftMargin: 6
          rightMargin: 6
          topMargin: 6
          spacing: 1
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          reuseItems: true
          model: panelRoot.rows

          delegate: Loader {
            required property var modelData
            width: listFlick.width - 12
            sourceComponent: modelData.isHeader ? headerDelegate : itemDelegate

            Component {
              id: headerDelegate
              Text {
                text: modelData.header
                color: panelRoot.mutedColor
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                topPadding: 8
                bottomPadding: 2
                leftPadding: 10
              }
            }
            Component {
              id: itemDelegate
              Rectangle {
                id: itemRow
                readonly property var it: modelData.item
                // Read directly from panelRoot.selIndex rather than a
                // baked-in modelData.isSel -- see the comment on `rows`
                // above for why (keeps the ListView's model stable across
                // selection changes).
                readonly property bool isSel: panelRoot.selIndex === modelData.idx
                readonly property bool big: panelRoot.hasQuery && it.top
                width: listFlick.width - 12
                height: big ? 40 : 26
                radius: 8
                color: itemRow.isSel ? "#353b45" : (rowMouse.containsMouse ? "#2f343e" : "transparent")

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  // See panelRoot.lastHoverGlobalPos above for why this
                  // checks *global* cursor position rather than reacting to
                  // every position-changed event directly.
                  onPositionChanged: (mouse) => {
                    if (panelRoot.suppressHoverSelect) return;
                    const g = rowMouse.mapToGlobal(mouse.x, mouse.y);
                    if (Math.abs(g.x - panelRoot.lastHoverGlobalPos.x) < 1 && Math.abs(g.y - panelRoot.lastHoverGlobalPos.y) < 1) return;
                    panelRoot.lastHoverGlobalPos = g;
                    if (panelRoot.selIndex !== modelData.idx) { panelRoot.selIndex = modelData.idx; panelRoot.msg = ""; panelRoot.armedId = ""; }
                  }
                  onClicked: { panelRoot.selIndex = modelData.idx; panelRoot.runItem(itemRow.it); }
                }

                Rectangle {
                  x: 10
                  anchors.verticalCenter: parent.verticalCenter
                  width: itemRow.big ? 36 : 24
                  height: itemRow.big ? 36 : 24
                  radius: 6
                  color: itemRow.isSel ? panelRoot.hoverColor : (itemRow.big ? "#2f343e" : "transparent")
                  Text {
                    anchors.centerIn: parent
                    text: Phosphor.icon(itemRow.it.icon)
                    font.family: "Phosphor"
                    font.pixelSize: itemRow.big ? 19 : 14
                    color: itemRow.isSel ? (itemRow.it.danger ? panelRoot.colors[1] : panelRoot.colors[0]) : "#7f848e"
                  }
                }
                Text {
                  id: labelText
                  anchors.left: parent.left
                  anchors.leftMargin: itemRow.big ? 56 : 44
                  anchors.verticalCenter: parent.verticalCenter
                  text: itemRow.it.label
                  font.family: "JetBrains Mono"
                  font.pixelSize: itemRow.big ? 14 : 12
                  color: itemRow.isSel ? panelRoot.fgColor : "#9da5b4"
                }
                Text {
                  // Faded the same as the keybind/state column on the
                  // right -- the label is what you're picking, this is
                  // just context for it, same visual weight as `right`.
                  anchors.left: labelText.right
                  anchors.leftMargin: 6
                  anchors.right: rightLabel.left
                  anchors.rightMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: (panelRoot.hasQuery && !itemRow.big) ? "" : (itemRow.it.sub || "")
                  font.family: "JetBrains Mono"
                  font.pixelSize: itemRow.big ? 14 : 12
                  color: panelRoot.mutedColor
                }
                Text {
                  id: rightLabel
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  text: itemRow.it.right || ""
                  font.family: "JetBrains Mono"
                  font.pixelSize: 12
                  color: itemRow.it.rightColor || panelRoot.mutedColor
                }
              }
            }
          }
        }

        Text {
          visible: panelRoot.hasQuery && panelRoot.list.length === 0
          x: listFlick.x + 10
          y: listFlick.y + 6
          text: "no matches for “" + panelRoot.query + "”"
          color: panelRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
        }

        // ----- preview panel -----
        // `previewImage` (unused today) is the hook a future clipboard/
        // emoji entry uses to show a real thumbnail here instead of an
        // icon glyph -- see the header comment.
        Rectangle {
          anchors.left: listFlick.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 240
          color: "#262a31"
          border.width: 1
          border.color: panelRoot.hoverColor

          // ----- clipboard preview override -----
          // Clipboard entries replace the whole generic icon/label/rows
          // layout below with the real decoded content: literal text (own
          // whitespace/newlines preserved, not the mangled single-line
          // cliphist-list preview) or a real image render. Fed by
          // clipPreview*/updateClipboardPreview() above.
          ColumnLayout {
            visible: previewCol.cur !== null && previewCol.cur.clipboardLine !== undefined
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Text {
              Layout.fillWidth: true
              text: panelRoot.clipPreviewIsImage ? "image" : "text"
              color: panelRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 11
            }

            Image {
              visible: panelRoot.clipPreviewIsImage
              Layout.fillWidth: true
              Layout.fillHeight: true
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              source: panelRoot.clipPreviewImagePath
              cache: false
            }

            Flickable {
              visible: !panelRoot.clipPreviewIsImage
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              contentWidth: width
              contentHeight: clipPreviewTextItem.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: clipPreviewTextItem
                width: parent.width
                text: panelRoot.clipPreviewLoading && panelRoot.clipPreviewText.length === 0 ? "loading…" : panelRoot.clipPreviewText
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: panelRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 11
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8
              Rectangle {
                implicitWidth: 20
                implicitHeight: 18
                radius: 4
                border.width: 1
                border.color: panelRoot.hoverColor
                Text { anchors.centerIn: parent; text: "⏎"; color: panelRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 12 }
              }
              Text {
                text: "copy to clipboard"
                color: panelRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 12
              }
            }
          }

          Column {
            id: previewCol
            visible: panelRoot.currentItem() !== null && (previewCol.cur === null || previewCol.cur.clipboardLine === undefined)
            x: 16
            y: 18
            width: parent.width - 32
            spacing: 10

            readonly property var cur: panelRoot.currentItem()

            Rectangle {
              width: 52
              height: 52
              radius: 12
              color: "#2f343e"
              border.width: 1
              border.color: panelRoot.hoverColor
              Image {
                visible: previewCol.cur && !!previewCol.cur.previewImage
                anchors.fill: parent
                anchors.margins: 1
                fillMode: Image.PreserveAspectCrop
                source: previewCol.cur && previewCol.cur.previewImage ? previewCol.cur.previewImage : ""
              }
              Text {
                visible: !previewCol.cur || !previewCol.cur.previewImage
                anchors.centerIn: parent
                // Emoji results show the real glyph here instead of the
                // generic Phosphor icon every other row falls back to --
                // "Phosphor" is an icon font and has no emoji of its own.
                text: previewCol.cur ? (previewCol.cur.emojiChar || Phosphor.icon(previewCol.cur.icon)) : ""
                font.family: previewCol.cur && previewCol.cur.emojiChar ? "Noto Color Emoji" : "Phosphor"
                font.pixelSize: previewCol.cur && previewCol.cur.emojiChar ? 30 : 26
                color: previewCol.cur && previewCol.cur.danger ? panelRoot.colors[1] : panelRoot.colors[0]
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: previewCol.cur ? previewCol.cur.label : ""
              color: panelRoot.fgColor
              font.family: "JetBrains Mono"
              font.weight: Font.DemiBold
              font.pixelSize: 15
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              visible: text.length > 0
              text: previewCol.cur ? (previewCol.cur.sub || "") : ""
              color: panelRoot.mutedColor
              font.family: "JetBrains Mono"
              font.pixelSize: 13
            }

            Rectangle { width: parent.width; height: 1; color: panelRoot.hoverColor }

            Column {
              width: parent.width
              spacing: 3
              Repeater {
                model: {
                  const cur = previewCol.cur;
                  if (!cur) return [];
                  if (cur.calc) {
                    const c = cur.calc, out = [{ k: "expr", v: c.pretty }];
                    if (c.frac) out.push({ k: "exact", v: c.frac, c: panelRoot.colors[2] });
                    if (c.piFrac) out.push({ k: "in π", v: c.piFrac, c: panelRoot.colors[2] });
                    if (c.sci) out.push({ k: "sci", v: c.sci });
                    if (c.hex) out.push({ k: "hex", v: c.hex, c: "#7f848e" });
                    if (c.bin) out.push({ k: "bin", v: c.bin, c: "#7f848e" });
                    if (c.autoClosed) out.push({ k: "note", v: "closed " + c.autoClosed + " paren" + (c.autoClosed > 1 ? "s" : ""), c: panelRoot.mutedColor });
                    if (!c.ok) out.push({ k: "error", v: c.reason, c: panelRoot.colors[1] });
                    if (c.ok) out.push({ k: "copies", v: c.raw, c: "#7f848e" });
                    return out;
                  }
                  const out = [{ k: "type", v: cur.cat }];
                  if (cur.right && /\+/.test(cur.right)) out.push({ k: "keys", v: cur.right, c: panelRoot.colors[2] });
                  if (cur.danger && panelRoot.armedId === (cur.id || cur.label)) out.push({ k: "status", v: "confirm?", c: panelRoot.colors[1] });
                  if (cur.command) out.push({ k: "runs", v: cur.command.join(" "), c: "#7f848e" });
                  return out;
                }
                delegate: RowLayout {
                  required property var modelData
                  width: previewCol.width
                  spacing: 8
                  Text { Layout.preferredWidth: 44; text: modelData.k; color: panelRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                  Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.v; color: modelData.c || panelRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                }
              }
            }

            Item { width: 1; height: 8 }

            RowLayout {
              spacing: 8
              visible: previewCol.cur !== null
              Rectangle {
                implicitWidth: 20; implicitHeight: 18; radius: 4
                border.width: 1; border.color: panelRoot.hoverColor
                Text { anchors.centerIn: parent; text: "⏎"; color: panelRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 12 }
              }
              Text {
                text: {
                  const cur = previewCol.cur;
                  if (!cur) return "";
                  if (cur.calc) return cur.calc.ok ? "copy result · saves as ans" : "nothing to copy";
                  if (cur.clipboardLine !== undefined) return "copy to clipboard";
                  if (cur.emojiChar) return "copy emoji";
                  if (cur.danger && panelRoot.armedId === (cur.id || cur.label)) return "press again to confirm";
                  if (cur.view) return "view";
                  if (cur.panel) return "open panel";
                  if (cur.fill) return "try it";
                  if (cur.danger) return "run (asks to confirm)";
                  return "run";
                }
                color: panelRoot.fgColor
                font.family: "JetBrains Mono"
                font.pixelSize: 12
              }
            }
          }
        }
      }

      // ----- about page -----
      Item {
        visible: panelRoot.aboutView
        width: parent.width
        height: visible ? 296 : 0

        RowLayout {
          x: 22
          y: 20
          width: parent.width - 44
          spacing: 20

          Text {
            Layout.alignment: Qt.AlignTop
            text: Phosphor.icon("info")
            font.family: "Phosphor"
            font.pixelSize: 64
            color: panelRoot.colors[0]
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
              spacing: 0
              Text { text: aboutData.user; color: panelRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
              Text { text: "@"; color: panelRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              Text { text: aboutData.host; color: panelRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
            }
            Text { text: "──────────────────"; color: panelRoot.hoverColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            Column {
              spacing: 0
              Repeater {
                model: [
                  { k: "os", v: "NixOS (CoelOS)" }, { k: "kernel", v: aboutData.kernel },
                  { k: "uptime", v: aboutData.uptime }, { k: "wm", v: aboutData.wm },
                  { k: "shell", v: aboutData.shell }, { k: "cpu", v: aboutData.cpu },
                  { k: "memory", v: aboutData.memory }, { k: "disk /", v: aboutData.disk },
                ]
                delegate: RowLayout {
                  required property var modelData
                  spacing: 10
                  Text { Layout.preferredWidth: 70; text: modelData.k; color: panelRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                  Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.v; color: panelRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                }
              }
            }
          }
        }
      }

      // ----- footer -----
      Item {
        width: parent.width
        height: footerRow.implicitHeight + 14

        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: panelRoot.hoverColor }
        Rectangle { anchors.fill: parent; color: "#252930" }

        RowLayout {
          id: footerRow
          x: 16
          y: 7
          width: parent.width - 32
          spacing: 14

          Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: panelRoot.msg.length > 0 ? panelRoot.msg
              : (panelRoot.aboutView ? "system › about"
                : panelRoot.hasQuery ? (panelRoot.list.length + " results")
                : panelRoot.categories[Math.min(panelRoot.catIndex, panelRoot.categories.length - 1)].label)
            color: panelRoot.msg.length > 0 ? (panelRoot.armedId.length > 0 ? panelRoot.colors[1] : panelRoot.colors[3]) : panelRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }

          Row {
            spacing: 14
            Repeater {
              model: panelRoot.aboutView
                ? [{ k: "esc", l: "back" }]
                : panelRoot.hasQuery
                  ? [{ k: "↑↓", l: "move" }, { k: "⏎", l: "run" }, { k: "esc", l: "clear" }]
                  : [{ k: "tab", l: "category" }, { k: "↑↓", l: "move" }, { k: "⏎", l: "run" }, { k: "esc", l: "close" }]
              delegate: Row {
                required property var modelData
                spacing: 4
                Text { text: modelData.k; color: panelRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                Text { text: modelData.l; color: panelRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              }
            }
          }
        }
      }
    }
  }

  // ----- about page real data -----
  property var aboutData: ({ user: "joelsgc", host: "", kernel: "", uptime: "", wm: "Hyprland", shell: "", cpu: "", memory: "", disk: "" })
  Process {
    id: aboutProc
    command: ["sh", "-c", "hostname; uname -r; cat /proc/uptime; grep -m1 'model name' /proc/cpuinfo; nproc; grep -E '^MemTotal:|^MemAvailable:' /proc/meminfo; df -B1 --output=used,size / | tail -1; zsh --version; hyprctl version | head -1"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n");
        const host = lines[0] || "";
        const kernel = lines[1] || "";
        const uptimeSec = parseFloat((lines[2] || "0").split(" ")[0]) || 0;
        const cpuModel = (lines[3] || "").split(":")[1];
        const cores = lines[4] || "";
        const memTotalKb = parseInt((lines[5] || "0").replace(/\D/g, "")) || 0;
        const memAvailKb = parseInt((lines[6] || "0").replace(/\D/g, "")) || 0;
        const diskParts = (lines[7] || "").trim().split(/\s+/);
        const diskUsed = parseInt(diskParts[0]) || 0, diskTotal = parseInt(diskParts[1]) || 1;
        const zshVer = (lines[8] || "").split(" ")[1] || "";
        const hyprVer = (lines[9] || "").replace(/^Hyprland\s*/, "").split(" ")[0] || "";

        const uh = Math.floor(uptimeSec / 3600), um = Math.floor((uptimeSec % 3600) / 60);
        const gb = b => (b / 1073741824).toFixed(1) + "G";

        panelRoot.aboutData = {
          user: "joelsgc", host: host.trim(),
          kernel: kernel.trim(),
          uptime: uh + "h " + String(um).padStart(2, "0") + "m",
          wm: "Hyprland " + hyprVer,
          shell: "zsh " + zshVer,
          cpu: (cpuModel ? cpuModel.trim() : "unknown") + " (" + cores.trim() + ")",
          memory: gb((memTotalKb - memAvailKb) * 1024) + " / " + gb(memTotalKb * 1024),
          disk: gb(diskUsed) + " / " + gb(diskTotal),
        };
      }
    }
  }
  Component.onCompleted: {
    aboutProc.running = true;
    panelRoot.emojiDb = panelRoot.openEmojiDb();
    panelRoot.emojiDbEnsureSchema();
    panelRoot.loadRecentEmoji();
  }
}

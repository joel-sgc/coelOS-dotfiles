import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import "../sysPanel/Phosphor.js" as Phosphor
import "../sysPanel/Calc.js" as Calc
import "backends"

// ===== LAUNCHER PANEL =====
// Content for Launcher.qml's Spotlight overlay -- ported from the "Spotlight"
// block in "Quickshell Example/Quickshell Bar.dc.html" (search row, category
// chips, list+preview, about page, footer), with real content in place of
// that mock's generic Arch placeholders (see home/rofi.nix for what this is
// actually replacing).
//
// Moved out of sysPanel/dropdowns/ into its own top-level launcher/ folder
// (2026-09-27, at the user's request) -- this was never a dropdown (those
// anchor under a bar button; this is a full-screen modal owned by
// Launcher.qml), and by the time it grew clipboard/emoji/ssh/calculator/
// toggle support it had become a single ~1500-line file mixing six
// largely-independent backends with the actual search/selection/UI logic.
// Non-visual backends (apps/ssh/clipboard-list/emoji/toggles/about) now
// live in launcher/backends/ as their own small Item-based components,
// instantiated below by id (apps/ssh/clipboard/emoji/toggles/about) --
// this file keeps only the state and logic that's genuinely about being
// *the launcher screen*: category/search construction, fuzzy matching,
// selection, keyboard handling, and the visual tree itself. The one
// exception is the clipboard *live preview* mechanism (real decoded
// content shown as you move selection) -- it stays here rather than in
// ClipboardBackend.qml because it's tightly coupled to this file's own
// `list`/`selIndex` state and drives preview-panel UI directly; splitting
// it out would trade a small win for a lot of forwarding-property
// indirection with nothing real to show for it.
//
// The preview panel takes either an icon glyph or an image (`previewImage`
// on each row) -- app search results are the first real use of that (via
// Quickshell.iconPath resolving each entry's real Icon= value).
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

  // ----- backends -----
  AppsBackend { id: apps }
  SshBackend { id: ssh }
  ClipboardBackend { id: clipboard }
  EmojiBackend { id: emoji }
  TogglesBackend { id: toggles }
  AboutBackend { id: about }

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
    toggles.refreshDnd();
    toggles.refreshMonochrome();
    apps.refresh();
    ssh.refresh();
    clipboard.refresh();
    if (emoji.entries.length === 0) emoji.refresh();
  }

  // ----- category/item data -----
  // Real commands/scripts from home/rofi.nix (coel-main-menu and its
  // sub-menus) and PowerDropdown.qml's session actions, not the mock's
  // Arch/fuzzel/kitty placeholders.
  // A function, not a static literal -- the toggles category's "right"
  // badges reflect real state (toggles.dndOn etc.), so this has to re-run
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
      { id: "ssh", label: "ssh", icon: "hard-drives", items: ssh.categoryItems() },
      { id: "toggles", label: "toggles", icon: "toggle-right", items: [
        { id: "dnd", label: "Do not disturb", sub: "silence notifications", icon: "bell-slash", right: toggles.dndOn ? "[on]" : "[off]", rightColor: toggles.dndOn ? colors[3] : mutedColor },
        { id: "awake", label: "Keep awake", sub: "inhibit idle & sleep", icon: "coffee", right: toggles.awakeOn ? "[on]" : "[off]", rightColor: toggles.awakeOn ? colors[3] : mutedColor },
        { id: "micmute", label: "Mute microphone", sub: "global input mute", icon: toggles.micMuted ? "microphone-slash" : "microphone", right: toggles.micMuted ? "[on]" : "[off]", rightColor: toggles.micMuted ? colors[3] : mutedColor },
        { id: "monochrome", label: "Monochrome", sub: "grayscale screen shader", icon: "circle-half", right: toggles.monochromeOn ? "[on]" : "[off]", rightColor: toggles.monochromeOn ? colors[3] : mutedColor },
        { id: "eyecandy", label: "Eye candy", sub: "animations, blur, rounding, fancy borders", icon: "sparkle", right: toggles.eyeCandyOff ? "[off]" : "[on]", rightColor: toggles.eyeCandyOff ? mutedColor : colors[3] },
      ] },
      { id: "capture", label: "capture", icon: "camera", items: [
        { label: "Screenshot", sub: "region → clipboard", icon: "selection", right: "print", command: ["coel-screenshot"] },
        { label: "Screen record", sub: "region → file", icon: "record", right: "", command: ["coel-screenrecord"] },
        { label: "Color picker", sub: "hex → clipboard", icon: "eyedropper", right: "", command: ["hyprpicker", "-a"] },
      ] },
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
      // Deliberately last: fuzzyList() builds search results by walking
      // `categories` in array order with no score-based sort across
      // categories (only the single best-scoring hit gets pulled to the
      // top as `top: true`), so a category's position here is also its
      // priority in mixed search results. Clipboard history is often long
      // and full of incidental substring hits (a copied line containing
      // "rebuild" was outranking the actual "Rebuild" system command) --
      // last among real categories means every other category's matches
      // sort ahead of it, while still landing before the emoji matches
      // fuzzyList() appends after this loop (so the overall order is:
      // other categories, then clipboard, then emoji).
      //
      // Real browsable category (not search-only like emoji/apps) --
      // clipboard.categoryItems() maps every real cliphist entry, capped
      // only by cliphist's own history size, not by us. The list below
      // is a virtualized ListView specifically so this doesn't mean
      // instantiating hundreds of QML rows at once when this chip is
      // selected with no search query.
      { id: "clipboard", label: "clipboard", icon: "clipboard-text", items: clipboard.categoryItems() },
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
      // Same reset-before-run requirement as ClipboardBackend.copyEntry() --
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
        // *used* (copied, not just scrolled past -- see emoji.recordUsed())
        // emoji are pulled to their own group up top and not duplicated
        // further down; everything else keeps Unicode's own curated
        // group/subgroup order from emoji-test.txt.
        if (emoji.entries.length === 0) return [];
        const recentSet = new Set(emoji.recentChars);
        const recentItems = emoji.recentChars
          .map(ch => emoji.entries.find(e => e.char === ch))
          .filter(e => !!e)
          .map(e => emoji.browseItem(e, "recently used"));
        const restItems = emoji.entries
          .filter(e => !recentSet.has(e.char))
          .map(e => emoji.browseItem(e, e.category));
        return recentItems.concat(restItems);
      }
      let matches = emoji.matches(q).slice(0, 50);
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
    apps.installed.forEach(app => {
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
    // which stays a separate, capped, search-only source (thousands of
    // entries is too many to ever browse as a static category list;
    // clipboard's own up-to-hundreds is fine now that the list rendering
    // is virtualized).
    const emojiMatchList = emoji.matches(q);
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
  function runItem(it, shiftHeld) {
    if (!it) return;
    if (it.sshHost !== undefined) {
      if (shiftHeld) {
        Quickshell.execDetached(["wl-copy", "ssh " + it.sshHost]);
        msg = "→ copied “ssh " + it.sshHost + "”";
      } else {
        Quickshell.execDetached(["ghostty", "-e", "ssh", it.sshHost]);
        msg = "→ ssh " + it.sshHost;
      }
      closeRequested();
      return;
    }
    if (it.clipboardLine !== undefined) {
      clipboard.copyEntry(it.clipboardLine);
      msg = "→ copied from clipboard history";
      closeRequested();
      return;
    }
    if (it.emojiChar) {
      Quickshell.execDetached(["wl-copy", it.emojiChar]);
      emoji.recordUsed(it.emojiChar);
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
    if (it.id === "dnd") { toggles.toggleDnd(); msg = "toggling do not disturb…"; return; }
    if (it.id === "awake") { toggles.toggleAwake(); msg = "keep awake " + (toggles.awakeOn ? "on" : "off"); return; }
    if (it.id === "micmute") { toggles.toggleMicMute(); msg = "microphone " + (toggles.micMuted ? "muted" : "unmuted"); return; }
    if (it.id === "monochrome") { toggles.toggleMonochrome(); msg = "toggling monochrome…"; return; }
    if (it.id === "eyecandy") { toggles.toggleEyeCandy(); msg = "eye candy " + (toggles.eyeCandyOff ? "off" : "on"); return; }
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
        runItem(currentItem(), (event.modifiers & Qt.ShiftModifier) !== 0);
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
                  if (cur.sshHost !== undefined) {
                    const out = [{ k: "host", v: cur.sshHostName }];
                    if (cur.sshUser) out.push({ k: "user", v: cur.sshUser });
                    out.push({ k: "port", v: String(cur.sshPort) });
                    if (cur.sshKey) out.push({ k: "key", v: cur.sshKey, c: "#7f848e" });
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
                  if (cur.sshHost !== undefined) return "enter: ssh in ghostty · shift+enter: copy command";
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
              Text { text: about.data.user; color: panelRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
              Text { text: "@"; color: panelRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
              Text { text: about.data.host; color: panelRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
            }
            Text { text: "──────────────────"; color: panelRoot.hoverColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
            Column {
              spacing: 0
              Repeater {
                model: [
                  { k: "os", v: "NixOS (CoelOS)" }, { k: "kernel", v: about.data.kernel },
                  { k: "uptime", v: about.data.uptime }, { k: "wm", v: about.data.wm },
                  { k: "shell", v: about.data.shell }, { k: "cpu", v: about.data.cpu },
                  { k: "memory", v: about.data.memory }, { k: "disk /", v: about.data.disk },
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
}

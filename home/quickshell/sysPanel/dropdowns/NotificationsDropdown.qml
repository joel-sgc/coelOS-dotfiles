import QtQuick
import "../.."
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import "../Phosphor.js" as Phosphor

// ===== NOTIFICATIONS DROPDOWN =====
// Ported from "example/Quickshell Bar.dc.html"'s notifications mock
// (nSeed/nPush/nVals/nKey in that file's inline script), the same
// direct-port-not-fresh-design approach CalendarDropdown.qml already used
// for its own mock.
//
// Phase 2: real data. `backend` (NotificationsBackend.qml, threaded down
// via Panel.qml the same way fgColor/mutedColor/etc already are) owns the
// actual history/dnd/muted-apps state; every action below (dismiss/mute/
// reply/actions/clear) calls straight into it instead of mutating a local
// array the way the Phase 1 sample-data version of this file did.
Item {
  id: dropdownRoot

  property color fgColor: "#abb2bf"
  property color mutedColor: "#5c6370"
  property color hoverColor: "#404754"
  property var colors: ["#61afef", "#ef596f", "#e5c07b", "#89ca78", "#d55fde"]
  property bool popupOpen: false
  property var backend: null

  signal closeRequested()

  // Stale-focused-hidden-TextInput gotcha, same as NetworkDropdown.qml --
  // reclaim keyboard focus every time this dropdown opens.
  //
  // Also marks everything read on open (matching the mock's own
  // nToggle handler -- capture which ids were unread *before* marking
  // read, so the blue "fresh" dot can still show for this viewing session
  // even though the underlying `read` flag flips immediately). This was
  // planned from the start (see this file's own `fresh` comment lower
  // down) but never actually got wired to the real backend in the Phase 2
  // rewrite -- confirmed live as a real bug, not just a cosmetic gap: with
  // nothing ever calling markAllRead(), `read` stayed false in SQLite for
  // nearly everything regardless of how long the dropdown had been looked
  // at, so a real restart correctly (if confusingly) showed the same
  // large unread count right back.
  onPopupOpenChanged: {
    if (popupOpen) {
      dropdownRoot.forceActiveFocus();
      freshIds = items.filter(n => !n.read).map(n => n.id);
      if (backend) backend.markAllRead();
    }
  }
  property var freshIds: []

  readonly property var items: backend ? backend.history : []
  // Expand/collapse is purely a display state -- not persisted, not part
  // of the backend's own history rows, just which hist_ids are currently
  // showing their full body instead of the 2-line clamp.
  property var expandedIds: []
  function toggleExpand(id) {
    const i = expandedIds.indexOf(id);
    expandedIds = i >= 0 ? expandedIds.filter(x => x !== id) : expandedIds.concat([id]);
  }

  property string query: ""
  property string viewMode: "split" // "list" | "split"
  readonly property bool dnd: backend ? backend.dnd : false
  readonly property var mutedApps: backend ? backend.mutedApps : []
  // Cancels any active reply the moment selection moves to a different
  // notification -- replying is tied to a specific id (replyingId), not to
  // `selId`, so without this a reply box could keep sitting open on a row
  // that's no longer even selected once j/k (or a click) moves elsewhere.
  //
  // Tracks the selected notification by id, not by its position in
  // `flatFiltered` -- history is newest-first and a new notification
  // arriving prepends to it, shifting every existing row's index down by
  // one. An index-based `sel` silently ends up pointing at a *different*
  // notification the instant that happens, which is exactly what made
  // "some notifications work, some don't" on reply: whichever one was
  // selected when a fresh notification landed got swapped out from under
  // the detail pane/reply box without any visible sign of it (confirmed
  // live -- startReply() was firing with the id the user actually clicked,
  // but `current` had already silently drifted to a different notification
  // by the time the isReplying binding re-evaluated).
  property int selId: -1
  onSelIdChanged: { replyingId = -1; replyText = ""; }
  property int replyingId: -1
  // Returns keyboard focus to dropdownRoot whenever reply mode ends
  // (sent, cancelled via Escape, or cancelled by the onSelChanged above) --
  // the reply TextInput (in NotificationRow.qml/NotificationDetail.qml)
  // grabs focus for itself the moment it starts replying, and nothing else
  // would otherwise give it back, leaving every keyboard shortcut (z, v,
  // j/k, ...) silently dead afterward.
  onReplyingIdChanged: if (replyingId < 0) dropdownRoot.forceActiveFocus()
  property string replyText: ""
  property bool clearArmed: false

  property string statusMsg: ""
  property color statusMsgColor: mutedColor
  Timer { id: statusTimer; interval: 2600; onTriggered: dropdownRoot.statusMsg = "" }
  function say(text, color) {
    statusMsg = text;
    statusMsgColor = color || mutedColor;
    statusTimer.restart();
  }

  Timer { id: clearArmTimer; interval: 3000; onTriggered: dropdownRoot.clearArmed = false }

  // ----- "show app" (v1 heuristic, no generic D-Bus mechanism exists) -----
  // Real notification senders don't reliably identify "their own window"
  // for the receiving daemon to focus -- `desktopEntry` (when a sender
  // sets it) or the app name are the closest things to go on. Matched
  // against Hyprland's own window class list, case-insensitively, since
  // that's the only real correlation available; a clean miss just reports
  // "no window found" rather than erroring.
  property string pendingOpenTarget: ""
  Process {
    id: openAppProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: {
        const target = dropdownRoot.pendingOpenTarget.toLowerCase();
        let matched = null;
        try {
          const clients = JSON.parse(text);
          matched = clients.find(c =>
            (c.class || "").toLowerCase() === target || (c.initialClass || "").toLowerCase() === target);
        } catch (e) {}
        if (matched) {
          Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + matched.address]);
          dropdownRoot.say("→ focused " + dropdownRoot.pendingOpenTarget);
        } else {
          dropdownRoot.say("no window found for " + dropdownRoot.pendingOpenTarget);
        }
      }
    }
  }

  // ----- relative-time labels + date-bucket grouping -----
  // Direct port of the mock's own rel()/grp() -- "now" bucket is anything
  // under 15 minutes old, then today/yesterday/older by calendar date, not
  // by app. Re-evaluated every 30s while open (Timer below), same
  // popupOpen-gated-polling convention NetworkDropdown.qml already uses
  // for its own live Timers.
  property var nowTick: new Date()
  Timer {
    interval: 30000
    running: dropdownRoot.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: dropdownRoot.nowTick = new Date()
  }
  readonly property int dayMs: 86400000
  function todayStart() {
    const d = new Date(nowTick);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }
  function hm(d) { return Qt.formatDateTime(d, "hh:mm"); }
  function relTime(ts) {
    const m = Math.floor((nowTick.getTime() - ts) / 60000);
    const d = new Date(ts);
    if (m < 1) return "now";
    if (m < 60) return m + "m ago";
    if (ts >= todayStart()) return hm(d);
    if (ts >= todayStart() - dayMs) return "yesterday " + hm(d);
    return Qt.formatDate(d, "d MMM") + " " + hm(d);
  }
  function groupKey(ts) {
    if (nowTick.getTime() - ts < 15 * 60000) return "now";
    if (ts >= todayStart()) return "earlier today";
    if (ts >= todayStart() - dayMs) return "yesterday";
    return "older";
  }
  function fullTime(ts) { return Qt.formatDateTime(new Date(ts), "ddd d MMM, hh:mm"); }

  // Satty's own notification "image"/icon hint is just its app icon (see
  // NotificationRow.qml's header comment -- confirmed against real SQLite
  // rows, not guessed), so there's no reliable image hint to preview the
  // actual screenshot from. Satty's body text *does* contain the real
  // saved path though (e.g. "File saved to '/home/.../shot.png'."), so
  // pull it out of there instead, scoped to this one app specifically --
  // not a generic "parse any body for a path" heuristic, since that would
  // be far too eager to match across arbitrary senders.
  function extractPreviewImage(n) {
    if (!n.app || n.app.toLowerCase() !== "satty" || !n.body) return "";
    const m = n.body.match(/'([^']+\.(?:png|jpe?g|webp|bmp))'/i);
    if (!m || !m[1].startsWith("/")) return "";
    return "file://" + m[1];
  }

  // Raw `items` (backend.history rows -- just id/dbusId/app/icon/image/
  // receivedAt/urgency/read) plus everything the UI needs that isn't
  // persisted on the row itself: a freshly computed `time` label,
  // `fresh` (which ids were unread at the moment the dropdown last opened
  // -- see onPopupOpenChanged above -- not simply `!read`, since `read`
  // itself now flips true immediately on open for real persistence, while
  // the blue dot should still show for the rest of this viewing session),
  // `hasImage`, local `expanded` state, and `actions`/`canReply` -- both
  // only meaningful while the underlying Notification is still live,
  // fetched fresh from the backend per item since a closed notification
  // can't be acted on anymore. Every other computed property below (and
  // every consumer, NotificationRow/NotificationDetail) reads this, never
  // `items` or `backend` directly.
  readonly property var rendered: items.map(n => Object.assign({}, n, {
    time: relTime(n.receivedAt),
    fresh: freshIds.indexOf(n.id) >= 0,
    hasImage: !!(n.image && n.image.length > 0),
    previewImage: extractPreviewImage(n),
    expanded: expandedIds.indexOf(n.id) >= 0,
    actions: backend ? backend.actionsFor(n.id) : [],
    canReply: backend ? backend.canReply(n.id) : false,
  }))

  function isMuted(app) { return mutedApps.indexOf(app) >= 0; }

  readonly property var filtered: {
    const q = query.trim().toLowerCase();
    return rendered.filter(n => !q || (n.app + " " + n.summary + " " + n.body).toLowerCase().includes(q));
  }
  readonly property var groups: {
    const order = ["now", "earlier today", "yesterday", "older"];
    const out = [];
    for (const key of order) {
      const its = filtered.filter(n => dropdownRoot.groupKey(n.receivedAt) === key);
      if (its.length > 0) out.push({ label: key, count: its.length, items: its });
    }
    return out;
  }
  readonly property var flatFiltered: filtered
  readonly property bool isEmpty: filtered.length === 0
  readonly property string emptyText: query.trim().length > 0
    ? ("no notifications match \"" + query.trim() + "\"")
    : "nothing here · all caught up"

  readonly property int unreadCount: items.filter(n => !n.read).length
  readonly property string statusText: unreadCount > 0 ? (unreadCount + " unread") : "✓ all read"
  readonly property color statusColor: unreadCount > 0 ? colors[2] : colors[3]

  readonly property var current: {
    const found = flatFiltered.find(n => n.id === selId);
    if (found) return found;
    return flatFiltered.length > 0 ? flatFiltered[0] : null;
  }
  readonly property var currentRows: current ? [
    { k: "app", v: current.app, c: fgColor },
    { k: "urgency", v: current.urgency, c: current.urgency === "critical" ? colors[1] : mutedColor },
    { k: "received", v: fullTime(current.receivedAt), c: mutedColor },
    { k: "id", v: "#" + current.id + " · org.freedesktop.Notifications", c: mutedColor },
  ] : []

  function selectId(id) { selId = id; }
  function dismiss(id) {
    if (backend) backend.dismiss(id);
    if (replyingId === id) { replyingId = -1; replyText = ""; }
  }
  function clearAll() {
    if (!clearArmed) {
      clearArmed = true;
      clearArmTimer.restart();
      // Short on purpose -- this lives in the header's status slot, which
      // overlapped the controls cluster in split view's one-line layout
      // when this message was its old, much longer self (confirmed live).
      say("clear " + items.length + "? confirm again", colors[1]);
      return;
    }
    const n = items.length;
    if (backend) backend.clearAll();
    clearArmed = false;
    say("→ cleared " + n + " notification" + (n === 1 ? "" : "s"));
  }
  function toggleDnd() {
    if (backend) backend.toggleDnd();
    say(dropdownRoot.dnd ? "do not disturb off" : "do not disturb on · critical still shows");
  }
  function toggleMute(app) {
    const wasMuted = isMuted(app);
    if (backend) backend.toggleMute(app);
    say(wasMuted ? ("unmuted " + app) : ("muted " + app + " · no popups, still logged here"));
  }
  function copyNotif(n) {
    Quickshell.execDetached(["wl-copy", n.summary + "\n\n" + n.body]);
    say("→ copied to clipboard");
  }
  function markRead(id) { if (backend) backend.markRead(id); }
  function openApp(n) {
    pendingOpenTarget = (n.desktopEntry && n.desktopEntry.length > 0)
      ? n.desktopEntry.replace(/\.desktop$/, "")
      : n.app;
    openAppProc.running = true;
  }
  function runAction(n, a) {
    say("→ " + a.label);
    if (backend) backend.invokeAction(n.id, a.id);
  }
  // Also pins `selId` to this exact notification -- `current` falls back
  // to "newest" whenever selId doesn't match anything (the default state
  // before the user has explicitly clicked a row), so replying to
  // whatever's currently on display without first clicking it left the
  // detail pane still silently following new arrivals: a message landing
  // mid-reply swapped `current` out from under the open reply box, same
  // bug class as the index-based `sel` this replaced, just reached via a
  // different path (confirmed live -- startReply fired with the right id,
  // but the next notification's arrival moved `current` again since
  // nothing had actually pinned selection to it).
  function startReply(n) { selId = n.id; replyingId = n.id; replyText = ""; }
  function sendReply() {
    if (replyingId < 0 || !replyText.trim()) return;
    if (backend) backend.sendReply(replyingId, replyText);
    say("→ reply sent");
    replyingId = -1;
    replyText = "";
  }

  focus: true
  Keys.onPressed: (event) => {
    // Reply fields live inside NotificationRow.qml/NotificationDetail.qml,
    // not here -- TextInput already consumes the character keys this
    // keymap cares about (d/r/m/c/...) while it holds focus, so no
    // explicit activeFocus check is needed for those the way searchInput
    // needs one below (it's the one text field this file owns directly).
    if (searchInput.activeFocus) {
      if (event.key === Qt.Key_Escape) { dropdownRoot.forceActiveFocus(); event.accepted = true; }
      return;
    }
    if (event.key === Qt.Key_Escape) {
      // Cancel reply first, then clear search, then close -- each Escape
      // undoes one thing rather than always closing the whole dropdown
      // outright (confirmed live: Escape while replying was closing
      // everything instead of just backing out of the reply box).
      if (replyingId >= 0) { replyingId = -1; replyText = ""; event.accepted = true; return; }
      if (query.length > 0) { query = ""; event.accepted = true; return; }
      closeRequested(); event.accepted = true; return;
    }
    if (event.key === Qt.Key_Slash) { searchInput.forceActiveFocus(); event.accepted = true; return; }
    if (event.key === Qt.Key_V || event.key === Qt.Key_Tab) { viewMode = viewMode === "list" ? "split" : "list"; event.accepted = true; return; }
    if (event.key === Qt.Key_Z) { toggleDnd(); event.accepted = true; return; }
    if (event.key === Qt.Key_C && (event.modifiers & Qt.ShiftModifier)) { clearAll(); event.accepted = true; return; }
    const list = flatFiltered;
    if (list.length === 0) { event.accepted = false; return; }
    let i = list.findIndex(x => x.id === selId);
    if (i < 0) i = 0;
    const n = list[i];
    switch (event.key) {
      case Qt.Key_J: case Qt.Key_Down: selId = list[Math.min(list.length - 1, i + 1)].id; event.accepted = true; break;
      case Qt.Key_K: case Qt.Key_Up: selId = list[Math.max(0, i - 1)].id; event.accepted = true; break;
      case Qt.Key_Return: case Qt.Key_Enter: openApp(n); event.accepted = true; break;
      // No canExpand guard here -- whether a body is actually truncated is
      // computed per-row (Text.truncated) inside NotificationRow.qml/
      // NotificationDetail.qml, not available from dropdownRoot. Toggling
      // "expanded" on a body that was never clamped is simply a no-op
      // visually, so there's nothing to gate.
      case Qt.Key_Space: case Qt.Key_E: toggleExpand(n.id); event.accepted = true; break;
      case Qt.Key_D: case Qt.Key_X: case Qt.Key_Delete: dismiss(n.id); event.accepted = true; break;
      case Qt.Key_C: copyNotif(n); event.accepted = true; break;
      case Qt.Key_R: if (n.canReply) startReply(n); event.accepted = true; break;
      case Qt.Key_M: toggleMute(n.app); event.accepted = true; break;
      case Qt.Key_1: case Qt.Key_2: case Qt.Key_3: {
        const idx = event.key - Qt.Key_1;
        if (n.actions[idx]) runAction(n, n.actions[idx]);
        event.accepted = true;
        break;
      }
      default: event.accepted = false;
    }
  }

  // Not a fixed implicitWidth like every other dropdown here -- split view
  // genuinely needs more horizontal room than list view (a 290px compact
  // list plus a flexible detail pane), and Panel.qml's Popup now auto-sizes
  // (contentWidth: 0) specifically so this can change live when `v` toggles
  // view mode instead of clipping against a fixed frame.
  implicitWidth: viewMode === "split" ? 700 : 480
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: 10

    // ----- header -----
    // Split view (700px) has room for title+stats and the controls
    // cluster on one shared line; list view (480px) doesn't -- the two
    // just overlapped when forced onto one line at that width (confirmed
    // live). So: one line in split mode, two lines in list mode, each
    // built from the same two reusable pieces (tabsComponent,
    // controlsComponent) via a Loader per spot rather than writing the
    // tabs/dnd/clear/close markup out twice.
    Component {
      id: tabsComponent
      Row {
        spacing: 2
        Repeater {
          model: [{ k: "list", l: "[list]" }, { k: "split", l: "[split]" }]
          delegate: Text {
            required property var modelData
            text: modelData.l
            color: dropdownRoot.viewMode === modelData.k ? dropdownRoot.fgColor : dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
            MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.viewMode = parent.modelData.k }
          }
        }
      }
    }

    Component {
      id: controlsComponent
      Row {
        spacing: 12

        // An Item wrapper with explicit x/y-positioned children, not a
        // Row -- anchoring a Row's own direct children (which both the
        // pill and the "dnd" label did, to vertically center against each
        // other) conflicts with Row's own x-positioning of those same
        // children; confirmed live as a real cause of header elements
        // rendering garbled/overlapping. A plain Item has no such
        // positioning claim over its children, so anchors on them (or on
        // the MouseArea filling the Item itself) are unambiguous.
        Item {
          id: dndToggle
          implicitWidth: dndLabel.x + dndLabel.implicitWidth
          implicitHeight: 18

          Rectangle {
            id: dndPill
            y: (parent.height - height) / 2
            width: 22; height: 12; radius: Globals.eyeCandyOff ? 0 : 6
            color: "transparent"
            border.width: 1
            border.color: dropdownRoot.dnd ? dropdownRoot.colors[1] : dropdownRoot.mutedColor
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              x: dropdownRoot.dnd ? (parent.width - width - 2) : 2
              width: 8; height: 8; radius: Globals.eyeCandyOff ? 0 : 4
              color: dropdownRoot.dnd ? dropdownRoot.colors[1] : dropdownRoot.mutedColor
              Behavior on x { NumberAnimation { duration: 120 } }
            }
          }
          Text {
            id: dndLabel
            x: dndPill.width + 6
            y: (parent.height - implicitHeight) / 2
            text: "dnd"
            color: dropdownRoot.dnd ? dropdownRoot.colors[1] : dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.toggleDnd() }
        }

        Text {
          text: dropdownRoot.clearArmed ? "[confirm?]" : "[clear all]"
          color: dropdownRoot.clearArmed ? dropdownRoot.colors[1] : dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.clearAll() }
        }
        Text {
          text: "[×]"
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.closeRequested() }
        }
      }
    }

    // Split mode: one line, controls cluster (tabs + divider + dnd/clear/
    // close bunched together) anchored to the right, same as every other
    // dropdown's own header in this codebase.
    Item {
      visible: dropdownRoot.viewMode === "split"
      width: parent.width
      height: Math.max(splitLeft.implicitHeight, splitRight.implicitHeight)

      Row {
        id: splitLeft
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text { id: splitTitleText; text: "notifications"; color: dropdownRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
        Text { id: splitCountText; text: "─ " + dropdownRoot.items.length + " ─"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        // Shows the transient action-confirmation message here (e.g.
        // "→ copied to clipboard") when there is one, falling back to the
        // normal unread-count status otherwise -- previously this message
        // replaced the footer's keybind legend instead, which meant the
        // legend kept vanishing every time an action ran. This status slot
        // already exists and is the more natural home for it.
        //
        // Bounded width + elide, not just a shorter default message --
        // this line shares the header with splitRight's own controls
        // cluster (unlike list mode's version below, which gets a whole
        // line to itself), and a long enough message visibly overlapped
        // it instead of being contained (confirmed live with the old,
        // longer clear-confirm wording).
        Text {
          text: dropdownRoot.statusMsg.length > 0 ? dropdownRoot.statusMsg : dropdownRoot.statusText
          color: dropdownRoot.statusMsg.length > 0 ? dropdownRoot.statusMsgColor : dropdownRoot.statusColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          elide: Text.ElideRight
          width: Math.max(40, dropdownRoot.width - splitTitleText.implicitWidth - splitCountText.implicitWidth - splitRight.implicitWidth - 60)
        }
      }

      Row {
        id: splitRight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Loader { sourceComponent: tabsComponent }
        Text { text: "│"; color: dropdownRoot.hoverColor; font.pixelSize: 13 }
        Loader { sourceComponent: controlsComponent }
      }
    }

    // List mode: two lines -- title+stats on its own line, then tabs at
    // the far left and the dnd/clear/close cluster at the far right of a
    // second line (not bunched together the way split mode has them --
    // there's no divider between them here since they're not adjacent).
    Column {
      visible: dropdownRoot.viewMode === "list"
      width: parent.width
      spacing: 6

      Row {
        id: listTitleRow
        spacing: 8
        Text { id: listTitleText; text: "notifications"; color: dropdownRoot.colors[0]; font.family: "JetBrains Mono"; font.weight: Font.DemiBold; font.pixelSize: 13 }
        Text { id: listCountText; text: "─ " + dropdownRoot.items.length + " ─"; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
        // Shows the transient action-confirmation message here (e.g.
        // "→ copied to clipboard") when there is one, falling back to the
        // normal unread-count status otherwise -- previously this message
        // replaced the footer's keybind legend instead, which meant the
        // legend kept vanishing every time an action ran. This status slot
        // already exists and is the more natural home for it. Nothing else
        // shares this line in list mode, but still bounded + elided
        // defensively so a long message can't widen the whole dropdown.
        Text {
          text: dropdownRoot.statusMsg.length > 0 ? dropdownRoot.statusMsg : dropdownRoot.statusText
          color: dropdownRoot.statusMsg.length > 0 ? dropdownRoot.statusMsgColor : dropdownRoot.statusColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          elide: Text.ElideRight
          width: Math.max(40, dropdownRoot.width - listTitleText.implicitWidth - listCountText.implicitWidth - 40)
        }
      }

      Item {
        width: parent.width
        height: Math.max(listTabs.implicitHeight, listControls.implicitHeight)

        Loader {
          id: listTabs
          sourceComponent: tabsComponent
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }
        Loader {
          id: listControls
          sourceComponent: controlsComponent
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // ----- search ----- (same structural pattern as LauncherPanel.qml's
    // own search row -- a RowLayout with an explicit height, a
    // Layout.fillWidth TextInput, and a placeholder Text parented *inside*
    // the TextInput itself, visible only while it's empty.)
    Rectangle {
      width: parent.width
      height: 30
      radius: Globals.eyeCandyOff ? 0 : 6
      color: "transparent"
      border.width: 1
      border.color: dropdownRoot.hoverColor

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        Text {
          text: Phosphor.icon("magnifying-glass")
          font.family: "Phosphor"
          font.pixelSize: 14
          color: dropdownRoot.mutedColor
        }
        TextInput {
          id: searchInput
          Layout.fillWidth: true
          text: dropdownRoot.query
          color: dropdownRoot.fgColor
          font.family: "JetBrains Mono"
          font.pixelSize: 13
          selectByMouse: true
          onTextEdited: dropdownRoot.query = text
          // Enter releases focus back to the dropdown's own keymap (j/k,
          // actions, ...) instead of leaving it stuck in the search box --
          // same "release focus when this text field's job is done" idea
          // as the reply field already does on send.
          onAccepted: dropdownRoot.forceActiveFocus()

          Text {
            visible: searchInput.text.length === 0
            text: "search history"
            color: dropdownRoot.mutedColor
            font.family: "JetBrains Mono"
            font.pixelSize: 13
          }
        }
        Text {
          visible: dropdownRoot.query.trim().length > 0
          text: dropdownRoot.filtered.length + " match" + (dropdownRoot.filtered.length === 1 ? "" : "es")
          color: dropdownRoot.mutedColor
          font.family: "JetBrains Mono"
          font.pixelSize: 12
        }
        Rectangle {
          implicitWidth: slashLabel.implicitWidth + 8
          implicitHeight: 16
          radius: Globals.eyeCandyOff ? 0 : 4
          color: "transparent"
          border.width: 1
          border.color: dropdownRoot.hoverColor
          Text { id: slashLabel; anchors.centerIn: parent; text: "/"; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 11 }
        }
      }
    }

    // ----- empty state -----
    Column {
      visible: dropdownRoot.isEmpty
      width: parent.width
      spacing: 8
      topPadding: 60
      bottomPadding: 60

      // horizontalAlignment, not anchors.horizontalCenter -- the latter on
      // a Column's own direct child is the same unsafe pattern flagged
      // throughout this file; Text's own alignment property has no such
      // conflict since it doesn't fight the Column for control of x.
      Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: Phosphor.icon("bell-simple-z"); font.family: "Phosphor"; font.pixelSize: 26; color: dropdownRoot.mutedColor }
      Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: dropdownRoot.emptyText; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 13 }
    }

    // ----- list view -----
    Column {
      visible: !dropdownRoot.isEmpty && dropdownRoot.viewMode === "list"
      width: parent.width
      spacing: 12

      Repeater {
        model: dropdownRoot.groups
        delegate: Column {
          id: groupCol
          required property var modelData
          width: parent.width
          spacing: 6

          // An Item, not a Row -- the divider line below needs both an
          // anchored vertical-center AND a width computed from its
          // siblings' positions, neither of which is safe to express on a
          // Row's own direct child (see the dnd toggle's own comment above
          // for why: anchors there fight the positioner's x/width
          // management of that same child).
          Item {
            width: parent.width
            height: 16
            Text { id: groupLabel; anchors.verticalCenter: parent.verticalCenter; text: groupCol.modelData.label; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            Text { id: groupCount; x: groupLabel.x + groupLabel.implicitWidth + 8; anchors.verticalCenter: parent.verticalCenter; text: groupCol.modelData.count; color: dropdownRoot.hoverColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            Rectangle { x: groupCount.x + groupCount.implicitWidth + 8; width: parent.width - x; height: 1; anchors.verticalCenter: parent.verticalCenter; color: dropdownRoot.hoverColor }
          }

          Repeater {
            model: groupCol.modelData.items
            delegate: NotificationRow {
              width: parent.width
              n: modelData
              nRoot: dropdownRoot
              selected: dropdownRoot.current && dropdownRoot.current.id === modelData.id
            }
          }
        }
      }
    }

    // ----- split view -----
    RowLayout {
      visible: !dropdownRoot.isEmpty && dropdownRoot.viewMode === "split"
      width: parent.width
      height: 440
      spacing: 14

      // A real ListView, not a Column+Repeater -- the latter had no
      // bound on its own total height, so once there were enough
      // notifications to exceed the split view's fixed 440px, the list
      // just spilled out past it and overlapped the footer's keybind
      // legend below (confirmed live). `clip: true` + the fixed-height
      // ListView itself is what actually contains it; same pattern
      // LauncherPanel.qml's own clipboard list already established for
      // "a list that can grow past its visible area."
      ListView {
        id: compactList
        Layout.preferredWidth: 220
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 4
        model: dropdownRoot.flatFiltered

        delegate: Rectangle {
          required property var modelData
          width: compactList.width
          // Was a flat 34 -- too short for its own two-line content (13px
          // summary + 11px app/time, 4px top padding, no bottom padding
          // at all), confirmed live: the selected item's border visibly
          // clipped the second line instead of containing it. Driven off
          // the actual content height plus matching top/bottom padding
          // instead of a guessed constant.
          implicitHeight: compactCol.implicitHeight + 12
          radius: Globals.eyeCandyOff ? 0 : 4
          color: dropdownRoot.current && dropdownRoot.current.id === modelData.id ? "#2f343e" : (compactMouse.containsMouse ? "#2f343e" : "transparent")
          border.width: 1
          // Same precedence as NotificationRow.qml's own card border:
          // critical always red, else selected gets blue, else a
          // visible default border instead of none.
          border.color: modelData.urgency === "critical" ? dropdownRoot.colors[1] : ((dropdownRoot.current && dropdownRoot.current.id === modelData.id) ? dropdownRoot.colors[0] : dropdownRoot.hoverColor)

          Column {
            id: compactCol
            x: 8
            y: 6
            width: parent.width - 16
            Text { text: modelData.summary; color: modelData.read ? dropdownRoot.mutedColor : dropdownRoot.fgColor; font.family: "JetBrains Mono"; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
            Text { text: modelData.app + " · " + modelData.time; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 11 }
          }
          MouseArea { id: compactMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dropdownRoot.selectId(modelData.id) }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Globals.eyeCandyOff ? 0 : 2
        color: "transparent"
        border.width: 1
        border.color: dropdownRoot.hoverColor

        NotificationDetail {
          anchors.fill: parent
          anchors.margins: 14
          n: dropdownRoot.current
          rows: dropdownRoot.currentRows
          nRoot: dropdownRoot
          visible: dropdownRoot.current !== null
        }
      }
    }

    // ----- footer -----
    // Always the keybind legend -- the transient action-confirmation
    // message moved to the header's status slot instead of living here,
    // since it used to replace this legend outright every time an action
    // ran (dismiss, copy, mute, ...), making the hints disappear
    // constantly instead of staying put as a reference.
    Item {
      width: parent.width
      implicitHeight: footerHints.implicitHeight

      Flow {
        id: footerHints
        width: parent.width
        spacing: 12
        Repeater {
          model: [
            { k: "j/k", l: "move" }, { k: "⏎", l: "show app" }, { k: "1–3", l: "actions" },
            { k: "d", l: "dismiss" }, { k: "r", l: "reply" }, { k: "c", l: "copy" },
            { k: "m", l: "mute" }, { k: "tab", l: "view" }, { k: "z", l: "dnd" },
          ]
          delegate: Row {
            required property var modelData
            spacing: 4
            Text { text: modelData.k; color: dropdownRoot.colors[2]; font.family: "JetBrains Mono"; font.pixelSize: 12 }
            Text { text: modelData.l; color: dropdownRoot.mutedColor; font.family: "JetBrains Mono"; font.pixelSize: 12 }
          }
        }
      }
    }
  }
}

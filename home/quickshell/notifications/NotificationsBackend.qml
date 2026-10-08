import QtQuick
import QtQuick.LocalStorage
import Quickshell
import Quickshell.Services.Notifications

// ===== NOTIFICATIONS BACKEND =====
// Phase 2: the real thing. Owns the actual org.freedesktop.Notifications
// D-Bus server (NotificationServer below) -- instantiating this is what
// makes Quickshell *become* the system notification daemon, replacing
// mako. Lives once, process-wide, instantiated from shell.qml inside
// Notifications.qml (never per-screen) -- registering the D-Bus service
// more than once would be wrong the same way a second mako process would
// be.
//
// History persists in real SQLite via QtQuick.LocalStorage, same pattern
// CalendarDropdown.qml already established for its own todos table (see
// that file's own header comment for the reasoning -- indexed queries over
// a flat JSON file, in case this ever needs more than today's flat
// "most recent 200" read).
//
// Data model consumed by NotificationsDropdown.qml / NotificationRow.qml /
// NotificationDetail.qml / the toast stack (Notifications.qml), one object
// per row of `history`:
//   { id, dbusId, app, icon, image, receivedAt, urgency, read, actions,
//     canReply }
// `icon` is always a generic Phosphor placeholder for now -- decoding a
// real per-app icon from the D-Bus spec's several possible hint shapes
// (themed name, file path, raw pixmap data) is deferred past v1, same as
// this project's "hardcoded UI first, real logic in a later pass"
// convention applied to everything else here; `image` (the notification's
// own image-path/data hint, when present) still renders for real via a
// plain Image element in the row components. `actions`/`canReply` are only
// ever non-empty while the underlying Notification is still live (present
// in `liveMap`) -- a closed notification can't be acted on for real
// anymore, only browsed.
Item {
  id: backend

  property bool dnd: false
  property var mutedApps: []
  // Newest first. Rebuilt (not mutated in place) on every change so every
  // binding that reads it -- dropdown, bell badge, toast stack -- updates
  // reactively, same reasoning CalendarDropdown's own `todos` cache
  // mirroring already relies on.
  property var history: []
  // dbusId (string) -> live Notification*, for notifications the server
  // still has open. Reassigned (not mutated in place) on every change for
  // the same reactivity reason as `history`.
  property var liveMap: ({})

  readonly property int unreadCount: history.filter(n => !n.read).length

  function isLive(dbusId) { return liveMap[String(dbusId)] !== undefined; }

  // ----- the real D-Bus server -----
  NotificationServer {
    id: server
    keepOnReload: true
    // Advertised capabilities -- only the ones actually implemented below.
    // bodyMarkupSupported/bodyHyperlinksSupported stay false: nothing here
    // renders rich text, so advertising support for it would just mean
    // senders format bodies this UI then shows as literal markup.
    persistenceSupported: true
    bodySupported: true
    bodyMarkupSupported: false
    bodyHyperlinksSupported: false
    bodyImagesSupported: true
    actionsSupported: true
    actionIconsSupported: false
    imageSupported: true
    inlineReplySupported: true

    onNotification: (n) => backend.handleNotification(n)
  }

  // ----- incoming notifications -----
  function handleNotification(n) {
    n.tracked = true;

    const urgencyStr = n.urgency === NotificationUrgency.Critical ? "critical"
      : n.urgency === NotificationUrgency.Low ? "low" : "normal";
    const receivedAt = Date.now();

    let histId = -1;
    db.transaction(function (tx) {
      // Number(...) -- LocalStorage's insertId comes back as a string, not
      // a JS number. Every other row id in this file (loadHistory's own
      // r.hist_id, the IPC debug path's parseInt(histId)) is a real
      // number, and replyingId/selId are both declared `property int`
      // (QML forces those to real numbers) -- a string id looks identical
      // in every console.log and even renders/selects fine (string id ===
      // string modelData.id both coming from the same row), but silently
      // fails the one comparison that matters against a real number:
      // `nRoot.replyingId === n.id` in NotificationDetail.qml's
      // isReplying, confirmed live as the actual reason reply looked like
      // it was doing nothing at all -- no error, isReplying just never
      // became true because "240" !== 240.
      histId = Number(tx.executeSql(
        "INSERT INTO history (dbus_id, app_name, app_icon, summary, body, urgency, image, received_at, read, close_reason, desktop_entry) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, ?)",
        [n.id, n.appName, n.appIcon, n.summary, n.body, n.urgency, n.image || "", receivedAt, n.desktopEntry || ""]
      ).insertId);
    });
    pruneHistory();

    const row = {
      id: histId, dbusId: n.id, app: n.appName, icon: "app-window", image: n.image || "",
      summary: n.summary, body: n.body || "", desktopEntry: n.desktopEntry || "",
      receivedAt: receivedAt, urgency: urgencyStr, read: false,
    };
    history = [row].concat(history).slice(0, 200);

    const next = Object.assign({}, liveMap);
    next[String(n.id)] = n;
    liveMap = next;

    n.closed.connect((reason) => backend.handleClosed(n.id, reason));

    const muted = mutedApps.indexOf(n.appName) >= 0;
    const show = !dnd || urgencyStr === "critical";
    if (show && !muted) pushToast(row, n);
  }

  function handleClosed(dbusId, reason) {
    const reasonStr = NotificationCloseReason.toString(reason);
    db.transaction(function (tx) {
      tx.executeSql("UPDATE history SET close_reason = ? WHERE dbus_id = ?", [reasonStr, dbusId]);
    });
    const next = Object.assign({}, liveMap);
    delete next[String(dbusId)];
    liveMap = next;
  }

  // ----- toasts -----
  // Capped at 3 simultaneous, newest last (matches the mock's own
  // `.slice(0, 3)`). `until` is null for critical (stays until manually
  // dismissed); Notifications.qml's own Timer ticks `pct` down from it and
  // calls fadeToast() when it runs out.
  readonly property int toastSeconds: 5
  property var toasts: []
  function pushToast(row, n) {
    const createdAt = Date.now();
    const toast = {
      id: row.dbusId, app: row.app, icon: row.icon, image: row.image,
      isCrit: row.urgency === "critical", summary: n.summary, body: n.body,
      createdAt: createdAt,
      until: row.urgency === "critical" ? null : (createdAt + toastSeconds * 1000),
    };
    toasts = [toast].concat(toasts).slice(0, 3);
  }
  // The popup timing out on its own is purely a display decision (how
  // long to show the toast) -- it used to also call n.expire() on the
  // real Notification, which closes it server-side for real and drops it
  // from `liveMap`. That made the dropdown's reply/action affordances
  // (canReply/actionsFor, both liveMap-gated) disappear the moment a
  // toast's 5s popup timer ran out, even though the notification itself
  // was still perfectly live and sitting in the dropdown -- confirmed
  // live as the cause of "the reply button goes away after a few
  // seconds". Only drops the visual toast; the real notification stays
  // open until the user actually dismisses it (below) or the sender
  // closes it.
  function fadeToast(dbusId) {
    toasts = toasts.filter(t => t.id !== dbusId);
  }
  // The user clicking a toast's own [×] -- this one really does close
  // the underlying Notification (CloseReason.Dismissed), same as
  // dismissing it from the dropdown.
  function dismissToast(dbusId) {
    toasts = toasts.filter(t => t.id !== dbusId);
    const n = liveMap[String(dbusId)];
    if (n) n.dismiss();
  }

  // ----- actions called from the dropdown -----
  // Both dismiss() and clearAll() used to only drop rows from the
  // in-memory `history` array, never actually deleting them from SQLite --
  // the UI looked right (empty) right up until the next real restart,
  // when loadHistory() reloaded every "dismissed" row right back from the
  // database, confirmed live (`clear all`, then a session restart, brought
  // back the full previous count). Both now really delete.
  function dismiss(histId) {
    const row = history.find(r => r.id === histId);
    history = history.filter(r => r.id !== histId);
    db.transaction(function (tx) { tx.executeSql("DELETE FROM history WHERE hist_id = ?", [histId]); });
    if (!row) return;
    const n = liveMap[String(row.dbusId)];
    if (n) n.dismiss();
  }
  function clearAll() {
    for (const row of history) {
      const n = liveMap[String(row.dbusId)];
      if (n) n.dismiss();
    }
    db.transaction(function (tx) { tx.executeSql("DELETE FROM history"); });
    history = [];
  }
  function markRead(histId) {
    db.transaction(function (tx) { tx.executeSql("UPDATE history SET read = 1 WHERE hist_id = ?", [histId]); });
    history = history.map(r => r.id === histId ? Object.assign({}, r, { read: true }) : r);
  }
  function markAllRead() {
    db.transaction(function (tx) { tx.executeSql("UPDATE history SET read = 1"); });
    history = history.map(r => Object.assign({}, r, { read: true }));
  }
  function toggleDnd() { dnd = !dnd; }
  function toggleMute(app) {
    const muted = mutedApps.indexOf(app) >= 0;
    db.transaction(function (tx) {
      if (muted) tx.executeSql("DELETE FROM muted_apps WHERE app_name = ?", [app]);
      else tx.executeSql("INSERT OR IGNORE INTO muted_apps (app_name) VALUES (?)", [app]);
    });
    mutedApps = muted ? mutedApps.filter(a => a !== app) : mutedApps.concat([app]);
  }
  function invokeAction(histId, actionId) {
    const row = history.find(r => r.id === histId);
    if (!row) return;
    const n = liveMap[String(row.dbusId)];
    if (!n) return;
    const action = n.actions.find(a => a.identifier === actionId);
    if (action) action.invoke();
  }
  function sendReply(histId, text) {
    const row = history.find(r => r.id === histId);
    if (!row || !text || !text.trim()) return;
    const n = liveMap[String(row.dbusId)];
    if (n && n.hasInlineReply) n.sendInlineReply(text);
  }
  // Real actions/reply only exist while the underlying Notification is
  // still live -- a closed one can only be browsed, per the D-Bus spec
  // (there's nothing left server-side to invoke or reply to).
  // Filters out the sender's own "mark as read"-style action -- KDE
  // Connect's messaging notifications carry one of these as a real action
  // (identifier "1" in practice, label "Mark as read") alongside
  // "inline-reply". Invoking it for real (action.invoke(), same as any
  // other action here) tells the sender the notification's been acted on,
  // and kdeconnected's own response to that is to close it server-side --
  // same consequence as the toast-timeout bug this replaced, just reached
  // by the user clicking what looks like an inert "mark read" chip instead
  // of a timer. We already have our own non-destructive local read flag
  // (dropdownRoot's own "[mark read]", markRead()/markAllRead() below) that
  // covers the same apparent purpose without closing anything, so the
  // sender's real version is redundant and only harmful here -- dropped
  // the same way "inline-reply" itself is already excluded from this list.
  function actionsFor(histId) {
    const row = history.find(r => r.id === histId);
    if (!row) return [];
    const n = liveMap[String(row.dbusId)];
    if (!n) return [];
    return n.actions
      .filter(a => a.text.trim().toLowerCase() !== "mark as read")
      .map(a => ({ id: a.identifier, label: a.text }));
  }
  function canReply(histId) {
    const row = history.find(r => r.id === histId);
    if (!row) return false;
    const n = liveMap[String(row.dbusId)];
    return n ? n.hasInlineReply : false;
  }

  // ----- persistence -----
  property var db: null
  function openDb() {
    return LocalStorage.openDatabaseSync(
      "CoelOSNotifications", "1.0",
      "Local notification history for the CoelOS quickshell bar", 1000000);
  }
  function dbEnsureSchema() {
    db.transaction(function (tx) {
      tx.executeSql("CREATE TABLE IF NOT EXISTS history (hist_id INTEGER PRIMARY KEY AUTOINCREMENT, dbus_id INTEGER, app_name TEXT, app_icon TEXT, summary TEXT, body TEXT, urgency INTEGER, image TEXT, received_at INTEGER, read INTEGER DEFAULT 0, close_reason TEXT)");
      tx.executeSql("CREATE TABLE IF NOT EXISTS muted_apps (app_name TEXT PRIMARY KEY)");
      // Added after history already existed on real dev machines this
      // session -- CREATE TABLE IF NOT EXISTS alone wouldn't add it to an
      // already-created table, so ALTER TABLE it in too, swallowing the
      // "duplicate column" error a second run of this would otherwise hit.
      try { tx.executeSql("ALTER TABLE history ADD COLUMN desktop_entry TEXT"); } catch (e) {}
    });
  }
  // Local id, deliberately distinct from the D-Bus notification id (only
  // guaranteed unique for the server's current process lifetime, not safe
  // as a permanent key across a hot-reload) -- see this project's own plan
  // notes on this.
  function loadHistory() {
    const out = [];
    db.transaction(function (tx) {
      const rs = tx.executeSql("SELECT hist_id, dbus_id, app_name, summary, body, urgency, image, received_at, read, desktop_entry FROM history ORDER BY hist_id DESC LIMIT 200");
      for (let i = 0; i < rs.rows.length; i++) {
        const r = rs.rows.item(i);
        out.push({
          id: Number(r.hist_id), dbusId: r.dbus_id, app: r.app_name, icon: "app-window", image: r.image || "",
          summary: r.summary, body: r.body || "", desktopEntry: r.desktop_entry || "",
          receivedAt: r.received_at, urgency: r.urgency === 2 ? "critical" : (r.urgency === 0 ? "low" : "normal"),
          read: r.read === 1,
        });
      }
    });
    history = out;
  }
  function loadMutedApps() {
    const out = [];
    db.transaction(function (tx) {
      const rs = tx.executeSql("SELECT app_name FROM muted_apps");
      for (let i = 0; i < rs.rows.length; i++) out.push(rs.rows.item(i).app_name);
    });
    mutedApps = out;
  }
  function pruneHistory() {
    db.transaction(function (tx) {
      tx.executeSql("DELETE FROM history WHERE hist_id NOT IN (SELECT hist_id FROM history ORDER BY hist_id DESC LIMIT 200)");
    });
  }

  Component.onCompleted: {
    db = openDb();
    dbEnsureSchema();
    loadHistory();
    loadMutedApps();
  }
}

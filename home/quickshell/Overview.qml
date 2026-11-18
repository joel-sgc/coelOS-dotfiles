import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

import "./overview"
import "./overview/Layout.js" as L

// ===== WORKSPACE OVERVIEW =====
// `quickshell ipc call overview open|close|toggle`, which the four-finger swipes in
// home/hyprland/hyprland.lua run. Lives in the panel's own process and is only
// built while open (LazyLoader), so it costs nothing the rest of the time. What it
// shows and how it animates: overview/OverviewPanel.qml.
Scope {
  id: scope

  property bool open: false

  // ---- four-finger swipes, followed live ----
  // Hyprland (patched, home/hyprland/hyprland.lua) reports each swipe as raw events
  // "coelswipe>>begin,<up|down>", ">>update,<tag>,<distance>", ">>end,<tag>,<distance>,<cancelled>".
  // Up on a closed overview opens it, the map following your fingers; down on an open
  // one takes it back. Letting go commits when you went far enough, or fast enough.
  readonly property real swipeSpan: 300       // distance (Hyprland's units) for a whole open/close
  property string swipeKind: ""               // "" | "open" | "close"
  property real swipeT: 0                     // the map's t as the fingers have it
  property real swipeVel: 0                   // t per second, recent
  property real swipeLastT: 0
  property real swipeLastMs: 0

  function swipePanel() { const w = loader.item; return w ? w.overviewPanel : null; }

  property real swipeBase: 0                  // t when the swipe took hold (0 or 1, or mid-animation)

  function onSwipe(data) {
    const p = data.split(",");
    const kind = p[0], tag = p[1];
    if (kind === "begin") {
      swipeKind = "";
      const panel = swipePanel();
      if (tag === "up" && !open) {
        swipeKind = "open"; swipeBase = 0; swipeT = 0;
        open = true;
      } else if (tag === "up" && panel && panel.phase === "closing" && panel.grab()) {
        // Swiped up again while it was still closing: take it back from where it is.
        swipeKind = "open"; swipeBase = panel.t; swipeT = panel.t;
      } else if (tag === "down" && panel && panel.grab()) {
        // (also mid-way through opening: whatever it was doing, your fingers have it now)
        swipeKind = "close"; swipeBase = panel.t; swipeT = panel.t;
      }
      swipeVel = 0; swipeLastT = swipeT; swipeLastMs = Date.now();
      return;
    }
    if (swipeKind === "" || tag !== (swipeKind === "open" ? "up" : "down")) return;
    const moved = (parseFloat(p[2]) || 0) / swipeSpan;
    const t = Math.max(0, Math.min(1, swipeKind === "open" ? swipeBase + moved : swipeBase - moved));
    if (kind === "update") {
      // Speed, smoothed. The first update arrives together with "begin" (same
      // instant), which says nothing about speed, so updates that close are skipped.
      const now = Date.now(), dt = now - swipeLastMs;
      if (dt >= 4) {
        swipeVel = 0.6 * swipeVel + 0.4 * (t - swipeLastT) / (dt / 1000);
        swipeLastT = t; swipeLastMs = now;
      }
      swipeT = t;
    } else if (kind === "end") {
      const cancelled = p[3] === "1";
      let goOpen;
      if (cancelled) goOpen = swipeKind === "close";
      else if (swipeKind === "open") goOpen = t >= 0.33 || swipeVel > 1.2;       // far enough, or a flick
      else goOpen = !(t <= 0.67 || swipeVel < -1.2);
      const panel = swipePanel();
      if (panel) panel.release(goOpen);
      else if (!goOpen) open = false;
      swipeKind = "";
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { if (event.name === "coelswipe") scope.onSwipe(event.data); }
  }

  IpcHandler {
    target: "overview"
    function open(): void { scope.open = true; }
    function close(): void { scope.requestClose(); }
    function toggle(): void { if (scope.open) scope.requestClose(); else scope.open = true; }
  }

  // Close the way Escape does: your current desktop zooms back to full size, and
  // the overlay goes away when that has played. (Switching `open` off directly would
  // remove it instantly.) With nothing to animate, just close.
  function requestClose() {
    const w = loader.item;
    if (w && w.overviewPanel) w.overviewPanel.dismiss();
    else scope.open = false;
  }

  function focusedScreen() {
    const mon = Hyprland.focusedMonitor;
    if (mon) for (const s of Quickshell.screens) if (s.name === mon.name) return s;
    return Quickshell.screens.length ? Quickshell.screens[0] : null;
  }

  LazyLoader {
    id: loader
    active: scope.open

    PanelWindow {
      id: win
      screen: scope.focusedScreen()
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; left: true; right: true; bottom: true }
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "coel-overview"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      property var rows: []
      property var clients: []                // `hyprctl clients`, kept so a moved window can be re-laid-out
      property var layoutOpts: ({})
      property int movedTo: 0                 // the workspace a window was just dropped on
      property bool dataReady: false
      property url wallpaper: ""


      // Everything it needs in one go, straight from Hyprland (its own idea of the
      // current workspace and monitor, not Quickshell's cached copy): the windows,
      // which workspace each row returns to (written by the Lua grid), the wallpaper,
      // the workspace you are on, and the monitors.
      Process {
        running: true
        command: ["sh", "-c",
          'hyprctl -j clients; printf "\\n@@\\n"; cat "$XDG_RUNTIME_DIR/coel-grid-rows" 2>/dev/null; printf "\\n@@\\n"; awww query 2>/dev/null; printf "\\n@@\\n"; hyprctl -j activeworkspace; printf "\\n@@\\n"; hyprctl -j monitors']
        stdout: StdioCollector {
          onStreamFinished: {
            const parts = text.split("\n@@\n");
            const json = (s, fallback) => { try { return JSON.parse(s); } catch (e) { return fallback; } };
            const clients = json(parts[0], []);
            const active = json(parts[3], {});
            const mons = json(parts[4], []);
            const mon = mons.find(m => m.focused) || mons[0] || {};
            win.clients = clients;
            win.layoutOpts = {
              monitorId: mon.id !== undefined ? mon.id : -1, monX: mon.x || 0, monY: mon.y || 0,
              monitors: mons,
              // The workspace this monitor shows (every monitor shows one of the shared grid).
              focusedId: mon.activeWorkspace && mon.activeWorkspace.id >= 1 ? mon.activeWorkspace.id : (active.id !== undefined ? active.id : -1),
              remembered: L.rememberedFor(parts[1] || "", mon.name || ""),
            };
            win.rows = L.rowsOf(clients, win.layoutOpts);
            // "eDP-1: 2256x1504, scale: 1, currently displaying: image: /path/to.jpg"
            const lines = (parts[2] || "").split("\n");
            const own = lines.find(l => mon.name && l.indexOf(mon.name + ":") >= 0) || lines[0] || "";
            const img = /image:\s*(\S.*?)\s*$/.exec(own);
            if (img) win.wallpaper = "file://" + img[1];
            win.dataReady = true;
          }
        }
      }

      // A moment after a drop: the windows as Hyprland has really arranged them now
      // (the dropped window's size and place, and its new neighbours'), and each picture
      // taken again as the rows are laid out afresh.
      Timer { id: refreshTimer; interval: 250; onTriggered: refresh.running = true }
      Process {
        id: refresh
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
          onStreamFinished: {
            let fresh = null;
            try { fresh = JSON.parse(text); } catch (e) { fresh = null; }
            if (!fresh) return;
            win.clients = fresh;
            win.rows = L.rowsOf(fresh, win.layoutOpts);
            if (win.movedTo) panel.selectId(win.movedTo);
          }
        }
      }

      readonly property var overviewPanel: panel

      OverviewPanel {
        id: panel
        anchors.fill: parent
        driven: scope.swipeKind === "open"
        dragT: scope.swipeT
        rows: win.rows
        dataReady: win.dataReady
        screenW: win.screen ? win.screen.width : 2256
        screenH: win.screen ? win.screen.height : 1504
        screenSource: win.screen
        wallpaper: win.wallpaper
        // hyprctl writes addresses as 0x59471d791ad0, Quickshell as 59471d791ad0.
        captureFor: function (address) {
          const want = String(address).replace(/^0x/i, "").toLowerCase();
          for (const t of Hyprland.toplevels.values) {
            if (String(t.address).replace(/^0x/i, "").toLowerCase() === want) return t.wayland || null;
          }
          return null;
        }
        // Hyprland's config is Lua: the grid (and each row's remembered column) lives
        // there. A row's own desktop goes through it; another workspace of the row is
        // focused directly.
        onChosen: (row, id, rep) => Hyprland.dispatch(rep
          ? "function() coel_grid.goto_row(" + row + ") end"
          : "function() hl.dispatch(hl.dsp.focus({ workspace = " + id + ", on_current_monitor = true })) end")
        // A window was dropped on another workspace: Hyprland moves it (it stays where
        // you are), and the map is laid out again with it in its new place.
        onWindowMoved: (address, workspace, fx, fy) => {
          // Hyprland moves it (you stay where you are), placing it on the side of the
          // workspace it was dropped on: the point is given in screen coordinates.
          const o = win.layoutOpts;
          Hyprland.dispatch("function() hl.dispatch(hl.dsp.window.move({ workspace = " + workspace
            + ", follow = false, window = \"address:" + address + "\", focal_x = "
            + Math.round((o.monX || 0) + fx * panel.screenW) + ", focal_y = "
            + Math.round((o.monY || 0) + fy * panel.screenH) + " })) end");
          // Show it at once, then (once Hyprland has re-tiled) take the real layout again.
          const list = win.clients.map(c => c.address === address
            ? Object.assign({}, c, { workspace: { id: workspace, name: String(workspace) } }) : c);
          win.clients = list;
          win.rows = L.rowsOf(list, win.layoutOpts);
          panel.selectId(workspace);
          win.movedTo = workspace;
          refreshTimer.restart();
        }
        onFinished: scope.open = false
      }
    }
  }
}

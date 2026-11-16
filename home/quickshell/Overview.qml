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
            win.rows = L.rowsOf(clients, {
              monitorId: mon.id !== undefined ? mon.id : -1, monX: mon.x || 0, monY: mon.y || 0,
              focusedId: active.id !== undefined ? active.id : -1, remembered: parts[1] || "",
            });
            // "eDP-1: 2256x1504, scale: 1, currently displaying: image: /path/to.jpg"
            const lines = (parts[2] || "").split("\n");
            const own = lines.find(l => mon.name && l.indexOf(mon.name + ":") >= 0) || lines[0] || "";
            const img = /image:\s*(\S.*?)\s*$/.exec(own);
            if (img) win.wallpaper = "file://" + img[1];
            win.dataReady = true;
          }
        }
      }

      readonly property var overviewPanel: panel

      OverviewPanel {
        id: panel
        anchors.fill: parent
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
        // there, so ask it to go to the row.
        onRowChosen: row => Hyprland.dispatch("function() coel_grid.goto_row(" + row + ") end")
        onFinished: scope.open = false
      }
    }
  }
}

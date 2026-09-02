import Quickshell.Bluetooth

// ===== BLUETOOTH =====
// Ported from home/waybar.nix's bluetooth module -- same icon states/glyphs
// (no controller and off/disabled all share one icon there too, so they
// collapse the same way here). No device-count tooltip -- that lived in
// waybar's tooltip, a real popup widget, out of scope here; the bar icon
// itself was always state-only, which is what this matches.
//
// Each state carries its own size, not one shared iconSize -- confirmed by
// eye that these three MDI glyphs are NOT uniform at the same pixel size:
// off/on match fine at 14, but "connected" (bluetooth-connect) renders
// visibly tinier than the other two at that size, needing a real bump to
// look consistent. Same MDI-inconsistency root cause as the original
// per-button iconSize tuning, just showing up *within* one button now that
// it swaps glyphs.
Button {
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property int connectedCount: {
    let n = 0;
    for (const d of Bluetooth.devices.values) {
      if (d.connected) n++;
    }
    return n;
  }

  readonly property var state: {
    if (!adapter || !adapter.enabled) return { icon: "󰂲", size: 14 };
    if (connectedCount > 0) return { icon: "󰂱", size: 20 };
    return { icon: "󰂯", size: 14 };
  }

  icon: state.icon
  iconSize: state.size
  command: [ "ghostty", "--class=com.joelsgc.floating", "-e", "bluepala" ]
}

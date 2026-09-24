.pragma library

// Phosphor icon codepoints, by name -- plain ASCII hex literals, never the
// glyphs themselves (see AGENTS.md: private-use characters are invisible
// to an AI assistant reading this file, so keeping them out of source
// entirely is what stops a rewrite from silently dropping one).
//
// Resolved to a real character at QML runtime via String.fromCharCode, so
// this works identically whether quickshell reads the deployed
// ~/.config/quickshell or this repo directly (home/hyprland.nix's
// exec-once uses -c straight at ./home/quickshell for quick reload while
// developing) -- unlike a Nix-build-time text substitution, there's no
// build step these codepoints depend on either way.
//
// Codepoints come from phosphor-icons/core's src/icons.ts (the "Regular"
// weight -- every weight shares the same codepoint per icon name, only the
// glyph shapes differ between font files).
const codepoints = {
  cpu: 0xe610, // ph-cpu

  bluetooth: 0xe0da, // ph-bluetooth
  "bluetooth-connected": 0xe0dc, // ph-bluetooth-connected
  "bluetooth-slash": 0xe0de, // ph-bluetooth-slash

  "wifi-high": 0xe4ea, // ph-wifi-high
  "wifi-medium": 0xe4ee, // ph-wifi-medium
  "wifi-low": 0xe4ec, // ph-wifi-low
  "wifi-slash": 0xe4f2, // ph-wifi-slash
  network: 0xedde, // ph-network (wired/ethernet)

  "speaker-high": 0xe44a, // ph-speaker-high
  "speaker-low": 0xe44c, // ph-speaker-low
  "speaker-x": 0xe45c, // ph-speaker-x (muted)

  "battery-full": 0xe0c0, // ph-battery-full (generic, non-tiered)
  "battery-charging": 0xe0ba, // ph-battery-charging
};

function icon(name) {
  const cp = codepoints[name];
  if (cp === undefined) {
    console.warn("Phosphor.icon: unknown icon name '" + name + "'");
    return "";
  }
  return String.fromCharCode(cp);
}

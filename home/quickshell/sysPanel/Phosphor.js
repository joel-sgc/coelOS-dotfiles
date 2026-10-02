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

  // PowerDropdown.qml
  lightning: 0xe2de, // ph-lightning (performance profile)
  scales: 0xe750, // ph-scales (balanced profile)
  leaf: 0xe2da, // ph-leaf (power-saver profile)
  lock: 0xe2fa, // ph-lock (lock)
  moon: 0xe330, // ph-moon (suspend)
  snowflake: 0xe5aa, // ph-snowflake (hibernate)
  "arrow-clockwise": 0xe036, // ph-arrow-clockwise (reboot)
  power: 0xe3da, // ph-power (shut down)

  // BluetoothDropdown.qml -- device-type icons
  headphones: 0xe2a6, // ph-headphones (also reused for earbuds -- no
  // dedicated Phosphor earbuds glyph)
  mouse: 0xe33a, // ph-mouse
  keyboard: 0xe2d8, // ph-keyboard
  "device-mobile": 0xe1e0, // ph-device-mobile (phone)
  question: 0xe3e8, // ph-question (unknown device)

  // NetworkDropdown.qml
  broadcast: 0xe0f2, // ph-broadcast (hotspot active)

  // AudioDropdown.qml
  microphone: 0xe326, // ph-microphone (source unmuted)
  "microphone-slash": 0xe328, // ph-microphone-slash (source muted)
  usb: 0xe956, // ph-usb (USB audio interface card icon)

  // LauncherPanel.qml -- category chips + item icons
  "rocket-launch": 0xe3fe, // ph-rocket-launch (launch category)
  "sidebar-simple": 0xec24, // ph-sidebar-simple (panels category)
  "toggle-right": 0xe676, // ph-toggle-right (toggles category)
  camera: 0xe10e, // ph-camera (capture category)
  palette: 0xe6c8, // ph-palette (style category)
  function: 0xebe4, // ph-function (math category)
  "gear-six": 0xe272, // ph-gear-six (system category)
  "magnifying-glass": 0xe30c, // ph-magnifying-glass (search input)
  calculator: 0xe538, // ph-calculator (calculator result row)

  "terminal-window": 0xeae8, // ph-terminal-window (Terminal)
  globe: 0xe288, // ph-globe (Browser)
  folder: 0xe24a, // ph-folder (Files)
  code: 0xe1bc, // ph-code (Editor)
  "music-notes": 0xe340, // ph-music-notes (Music)
  "squares-four": 0xe464, // ph-squares-four (App launcher)

  "speaker-simple-high": 0xe450, // ph-speaker-simple-high (Audio panel)
  "battery-high": 0xe0c2, // ph-battery-high (Power panel)
  "calendar-blank": 0xe10a, // ph-calendar-blank (Calendar panel)

  "bell-slash": 0xe0d4, // ph-bell-slash (Do not disturb)
  "moon-stars": 0xe58e, // ph-moon-stars (Night light)
  coffee: 0xe1c2, // ph-coffee (Keep awake)
  "battery-plus": 0xe808, // ph-battery-plus (Charge limit)

  selection: 0xe69a, // ph-selection (Screenshot region)
  "app-window": 0xe5da, // ph-app-window (Screenshot window)
  monitor: 0xe32e, // ph-monitor (Screenshot screen)
  record: 0xe3ee, // ph-record (Record region)
  eyedropper: 0xe568, // ph-eyedropper (Color picker)
  "text-aa": 0xe6ee, // ph-text-aa (Text from region / OCR)

  swatches: 0xe5b8, // ph-swatches (theme entries)
  image: 0xe2ca, // ph-image (Next wallpaper)
  "sliders-horizontal": 0xe434, // ph-sliders-horizontal (Edit bar config)

  info: 0xe2ce, // ph-info (About this system)
  "arrows-clockwise": 0xe094, // ph-arrows-clockwise (Update packages)
  "arrow-counter-clockwise": 0xe038, // ph-arrow-counter-clockwise (Reload shell)

  clipboard: 0xe196, // ph-clipboard (clipboard history entries)
  "clipboard-text": 0xe198, // ph-clipboard-text (clipboard category)
  smiley: 0xe436, // ph-smiley (emoji search results)
  "circle-half": 0xe18c, // ph-circle-half (monochrome toggle)
  sparkle: 0xe6a2, // ph-sparkle (eye candy toggle)
  "hard-drives": 0xe2a0, // ph-hard-drives (ssh category, tagged "servers")
  "arrows-left-right": 0xe0a0, // ph-arrows-left-right (convert category/results)
  trash: 0xe4a6,

  // lock/ -- lock screen (media transport, password field, power buttons)
  "skip-back": 0xe5a4, // ph-skip-back (media prev)
  "skip-forward": 0xe5a6, // ph-skip-forward (media next)
  play: 0xe3d0, // ph-play (media toggle, paused state)
  pause: 0xe39e, // ph-pause (media toggle, playing state)
  "lock-simple": 0xe308, // ph-lock-simple (password field prefix icon)
  "lock-simple-open": 0xe30a, // ph-lock-simple-open (auth success state)
  eye: 0xe220, // ph-eye (show password)
  "eye-slash": 0xe224, // ph-eye-slash (hide password)
  "arrow-right": 0xe06c, // ph-arrow-right (password submit button)
  fingerprint: 0xe23e, // ph-fingerprint (fingerprint button)
  users: 0xe4d6, // ph-users (switch-user button)
  "caret-left": 0xe138, // ph-caret-left (session switcher prev)
  "caret-right": 0xe13a, // ph-caret-right (session switcher next)
  "arrow-fat-up": 0xe52e, // ph-arrow-fat-up (caps-lock warning)
  check: 0xe182, // ph-check (auth success status line)
  x: 0xe4f6, // ph-x (auth error status line)
  "circle-notch": 0xeb44, // ph-circle-notch ("checking..." status line)

  // powermenu/ -- PowerMenu.qml
  "sign-out": 0xe42a, // ph-sign-out (log out tile)
  warning: 0xe4e0, // ph-warning (armed/countdown status line)
};

function icon(name) {
  const cp = codepoints[name];
  if (cp === undefined) {
    console.warn("Phosphor.icon: unknown icon name '" + name + "'");
    return "";
  }
  return String.fromCharCode(cp);
}

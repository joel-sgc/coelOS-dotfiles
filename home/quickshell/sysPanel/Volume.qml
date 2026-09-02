import Quickshell.Services.Pipewire

// ===== VOLUME =====
// Ported from home/waybar.nix's pulseaudio module -- same mute/3-tier
// glyphs (format-muted and the low tier share one icon there too, so they
// collapse the same way here). Skipped waybar's separate "headphone" icon
// (auto-swapped when the active sink's port is a headphone jack) -- that
// needs parsing PwNode.properties' port info, a bigger addition than "make
// it respond to status" calls for. volume is a 0..1 fraction (confirmed
// live -- this laptop's real default sink read back 0.9), same as
// UPower's battery percentage.
//
// PwObjectTracker is required for a PwNode's properties (audio.volume/
// muted) to actually stay populated/reactive -- Pipewire nodes are inert
// until something tracks them, confirmed live (untracked, volume/muted
// never updated after the first read).
//
// All three tiers carry the same size for now -- unlike bluetooth's mixed
// MDI glyphs, these are all Font Awesome from the same source family, so
// there's less reason to expect the same per-glyph drift, but each is
// still independently tunable (see Bluetooth.qml) if one of them turns
// out to not match once you actually see it.
Button {
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
  readonly property var icons: [
    { icon: "", size: 22 },
    { icon: "", size: 22 },
    { icon: "", size: 22 }
  ]

  readonly property var state: muted
    ? icons[0]
    : icons[Math.min(icons.length - 1, Math.floor(vol * icons.length))]

  icon: state.icon
  iconSize: state.size
  label: muted ? "" : Math.round(vol * 100) + "%"
  command: [ "ghostty", "--class=com.joelsgc.floating", "-e", "pulsemixer" ]

  PwObjectTracker {
    objects: sink ? [ sink ] : []
  }
}

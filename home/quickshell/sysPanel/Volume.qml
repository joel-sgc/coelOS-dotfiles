import Quickshell.Services.Pipewire
import "./Phosphor.js" as Phosphor

// ===== VOLUME =====
// Ported from home/waybar.nix's pulseaudio module -- muted gets its own
// dedicated glyph now (Phosphor has speaker-x) rather than reusing the
// quietest tier's icon the way waybar's format-muted did. Skipped waybar's
// separate "headphone" icon (auto-swapped when the active sink's port is a
// headphone jack) -- that needs parsing PwNode.properties' port info, a
// bigger addition than "make it respond to status" calls for. volume is a
// 0..1 fraction (confirmed live -- this laptop's real default sink read
// back 0.9), same as UPower's battery percentage.
//
// PwObjectTracker is required for a PwNode's properties (audio.volume/
// muted) to actually stay populated/reactive -- Pipewire nodes are inert
// until something tracks them, confirmed live (untracked, volume/muted
// never updated after the first read).
Button {
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
  readonly property var icons: [
    Phosphor.icon("speaker-low"),
    Phosphor.icon("speaker-high")
  ]

  // Not "state" -- Item already has a built-in `state` (QtQuick's States
  // system), and redeclaring it collides rather than overrides.
  readonly property var iconState: muted
    ? Phosphor.icon("speaker-x")
    : icons[Math.min(icons.length - 1, Math.floor(vol * icons.length))]

  icon: iconState
  label: muted ? "" : Math.round(vol * 100) + "%"
  active: root.openPopup === "audio"
  onClicked: root.openPopup = root.openPopup === "audio" ? "" : "audio"

  PwObjectTracker {
    objects: sink ? [ sink ] : []
  }
}

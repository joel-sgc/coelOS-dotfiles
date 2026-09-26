import QtQuick.Layouts

// ===== BUTTONS =====
// Right-hand button group, in the same order as home/waybar.nix's
// modules-right (tray, bluetooth, network, pulseaudio, cpu, battery).
// Every one of these now sources real live state (bluetooth/network/volume
// via Quickshell's own Bluetooth/Networking/Pipewire services, cpu/battery
// as before) -- see each file for how. A "•" (BulletDivider.qml) between
// each of the actual panel chips, not just whitespace -- the mock's
// tight 4px gap alone read as too cramped to tell adjacent chips apart
// at a glance. Nothing extra between Tray and Bluetooth: Tray.qml
// already carries its own trailing line divider, conditional on the
// tray actually having icons in it.
RowLayout {
  spacing: 8

  Tray {}
  Bluetooth {}
  BulletDivider {}
  Network {}
  BulletDivider {}
  Volume {}
  BulletDivider {}
  Cpu {}
  BulletDivider {}
  Battery {}
}

import QtQuick.Layouts

// ===== BUTTONS =====
// Right-hand button group, in the same order as home/waybar.nix's
// modules-right (tray, bluetooth, network, pulseaudio, cpu, battery).
// Every one of these now sources real live state (bluetooth/network/volume
// via Quickshell's own Bluetooth/Networking/Pipewire services, cpu/battery
// as before) -- see each file for how. spacing matches the mock's tight
// 4px gap between button-group chips (each Button already carries its own
// 7px internal padding, so 4px between chips still reads as comfortably
// spaced, not cramped).
RowLayout {
  spacing: 4

  Tray {}
  Bluetooth {}
  Network {}
  Volume {}
  Cpu {}
  Battery {}
}

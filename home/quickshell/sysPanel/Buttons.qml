import QtQuick.Layouts

// ===== BUTTONS =====
// Right-hand button group, in the same order as home/waybar.nix's
// modules-right (tray, bluetooth, network, pulseaudio, cpu, battery).
// Every one of these now sources real live state (bluetooth/network/volume
// via Quickshell's own Bluetooth/Networking/Pipewire services, cpu/battery
// as before) -- see each file for how, and for each one's own iconSize
// tuning.
RowLayout {
  spacing: 16

  Tray {}
  Bluetooth {}
  Network {}
  Volume {}
  Cpu {}
  Battery {}
}

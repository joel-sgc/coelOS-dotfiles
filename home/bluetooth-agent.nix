{ config, pkgs, ... }:

{
  # Registers a NoInputNoOutput bluetooth pairing agent for the whole
  # session -- without *any* agent registered, BlueZ's Pair() D-Bus call
  # fails for basically every real device, even "Just Works" SSP (which
  # needs zero user interaction, but still needs *some* agent registered).
  # No blueman/bluedevil or anything else already provides one here.
  #
  # bluetoothctl doubles as a minimal agent via its --agent flag:
  # NoInputNoOutput auto-accepts confirmation/authorization requests,
  # covering "Just Works" SSP (most consumer headphones/speakers/mice/
  # keyboards) but not devices needing real Numeric Comparison or
  # Passkey/PIN entry, which a NoInputNoOutput agent has no I/O to satisfy.
  # See the TODO(bluetooth pairing UI) note at the top of
  # BluetoothDropdown.qml for what a real fix needs.
  systemd.user.services.bluetooth-agent = {
    Unit = {
      Description = "Bluetooth pairing agent (auto-accept, no PIN/passkey UI)";
      After = [ config.wayland.systemd.target ];
      PartOf = [ config.wayland.systemd.target ];
    };
    Service = {
      Type = "simple";
      # bluetoothctl is an interactive REPL: with stdin at the default
      # /dev/null a systemd service gets, it reads EOF immediately and
      # quits, unregistering the agent it just added. `tail -f /dev/null`
      # as a stdin source never produces data and never closes, so
      # bluetoothctl just blocks waiting for a command that never comes --
      # exactly "stay registered, do nothing else".
      ExecStart = "${pkgs.bash}/bin/bash -c 'tail -f /dev/null | ${pkgs.bluez}/bin/bluetoothctl --agent NoInputNoOutput'";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}

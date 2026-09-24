{ config, pkgs, ... }:

{
  # Registers a NoInputNoOutput bluetooth pairing agent for the whole
  # session -- without *any* agent registered, BlueZ's Pair() D-Bus call
  # fails for basically every real device (confirmed live: pairing
  # headphones via BluetoothDropdown.qml got partway through, then failed
  # and reverted to unpaired, because there was nothing on the bus to
  # answer BlueZ's authentication callbacks -- not even "Just Works" SSP,
  # which needs zero user interaction, works without *some* agent
  # registered). Checked: no blueman/bluedevil or anything else was
  # already providing one here.
  #
  # bluetoothctl doubles as a minimal agent implementation via its
  # --agent flag: NoInputNoOutput auto-accepts confirmation/authorization
  # requests instead of prompting, which covers "Just Works" SSP pairing
  # (most consumer headphones/speakers/mice/keyboards) but not devices
  # that require real Numeric Comparison or Passkey/PIN entry -- a
  # NoInputNoOutput agent has no I/O capability to satisfy that. See the
  # TODO(bluetooth pairing UI) note at the top of BluetoothDropdown.qml
  # for what a real fix needs; left for later on purpose, not an
  # oversight.
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
      # treats that as an implicit "quit" -- confirmed live, it logs
      # "Agent registered" and then exits right away, unregistering the
      # agent it just added a moment before. `tail -f /dev/null` as a
      # stdin source never produces data and never closes, so
      # bluetoothctl just blocks waiting for a command that never comes
      # -- exactly what's wanted for "stay registered, do nothing else".
      ExecStart = "${pkgs.bash}/bin/bash -c 'tail -f /dev/null | ${pkgs.bluez}/bin/bluetoothctl --agent NoInputNoOutput'";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}

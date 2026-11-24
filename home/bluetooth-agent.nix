{ config, pkgs, ... }:

let
  # coel-bt-agent: a BlueZ pairing agent (KeyboardDisplay) that forwards its
  # questions -- compare this passkey, type a PIN, authorize a service -- to the
  # Quickshell bluetooth dropdown over $XDG_RUNTIME_DIR/coel-bt-agent.sock.
  # Protocol and fallback behaviour are documented at the top of the script;
  # tests: home/bluetooth-agent/test_coel_bt_agent.py.
  python = pkgs.python3.withPackages (ps: [ ps.dbus-fast ]);
  agent = pkgs.writeShellScriptBin "coel-bt-agent" ''
    exec ${python}/bin/python3 ${./bluetooth-agent/coel_bt_agent.py} "$@"
  '';
in
{
  home.packages = [ agent ];

  # Replaces the old `bluetoothctl --agent NoInputNoOutput` service, which
  # auto-accepted everything and could not do passkey / PIN pairing at all.
  # With no UI connected the new agent behaves the same way (confirmations
  # and authorizations accepted, typed-input requests rejected), so nothing
  # regresses while the dropdown is closed. It registers itself as the
  # default agent and re-registers if bluetoothd restarts.
  systemd.user.services.bluetooth-agent = {
    Unit = {
      Description = "Bluetooth pairing agent (forwards passkey/PIN requests to the shell)";
      After = [ config.wayland.systemd.target ];
      PartOf = [ config.wayland.systemd.target ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${agent}/bin/coel-bt-agent";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}

# Google Cast sender: cast the screen to Chromecasts, Google TVs, Nest speakers/displays and Cast-enabled TVs.
#
# Not Chrome's low-latency mirroring protocol: the screen is encoded to a live HLS stream, served over HTTP to the
# device, and the Default Media Receiver is told to play it (see README.md). No daemon is needed: `coel-gcast` starts
# the engine as a transient user service per cast. Discovery uses avahi (mDNS).
{ config, lib, pkgs, ... }:

let
  cfg = config.services.gcast;

  gstPlugins = with pkgs.gst_all_1; [
    (lib.getLib gstreamer)
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad # hlssink2, fdkaacenc, mpegtsmux
    gst-plugins-ugly # x264enc
    pkgs.pipewire # pipewiresrc
  ];

  # dbus-fast: the screen-capture portal client (modules/castlib). The Cast protocol itself is stdlib-only.
  python = pkgs.python3.withPackages (ps: [ ps.dbus-fast ]);

  engine = pkgs.writeShellScript "gcast-source" ''
    export PATH=${lib.makeBinPath [ pkgs.gst_all_1.gstreamer.bin ]}:$PATH
    export GST_PLUGIN_SYSTEM_PATH_1_0=${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}
    export PYTHONPATH=${../castlib}''${PYTHONPATH:+:$PYTHONPATH}
    exec ${python}/bin/python3 ${./engine}/gcast_engine.py "$@"
  '';

  ctl = pkgs.writeShellScriptBin "coel-gcast" ''
    export PATH=${lib.makeBinPath [ pkgs.avahi ]}:$PATH
    export GCAST_ENGINE=${engine}
    export GCAST_ENGINE_DIR=${./engine}
    export GCAST_HTTP_PORT=${toString cfg.httpPort}
    export GCAST_SYSTEMD_RUN=${pkgs.systemd}/bin/systemd-run
    export GCAST_SYSTEMCTL=${pkgs.systemd}/bin/systemctl
    export GCAST_JOURNALCTL=${pkgs.systemd}/bin/journalctl
    exec ${pkgs.python3}/bin/python3 ${./ctl/gcast_ctl.py} "$@"
  '';
in
{
  options.services.gcast = {
    enable = lib.mkEnableOption "casting the screen to Google Cast devices (coel-gcast)";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8765;
      description = ''
        TCP port of the HLS server the Cast device fetches the stream from. The device initiates the connection, so
        it must be open in the firewall (see openFirewall). The URL carries a random token and only the device's
        address is served, so the screen is not published to the rest of the LAN.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open httpPort in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.avahi.enable;
        message = "services.gcast needs services.avahi.enable = true (device discovery uses mDNS).";
      }
    ];

    environment.systemPackages = [ ctl ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.httpPort ];
  };
}

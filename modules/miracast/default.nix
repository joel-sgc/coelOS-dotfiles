# Miracast (Wi-Fi Display) source support, built as separate layers so no
# single front end is baked in. See README.md for the design and status.
#
#   services.miracast.enable = true;
#
# Phase 1 (this module): `miracast-linkd`, a root daemon that talks to
# wpa_supplicant directly (NetworkManager's Wi-Fi P2P support drops the peers,
# see README.md), finds Miracast sinks, and publishes them through a state file
# and a control socket that any client can use. `coel-miracast` is the first
# such client.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.miracast;

  # The wpa_supplicant unit(s): one per interface once networking.wireless.interfaces is set.
  wpaUnits =
    if config.networking.wireless.interfaces == [ ] then
      [ "wpa_supplicant.service" ]
    else
      map (i: "wpa_supplicant-${i}.service") config.networking.wireless.interfaces;

  python = pkgs.python3.withPackages (ps: [ ps.dbus-fast ]);

  linkd = pkgs.writeShellScript "miracast-linkd" ''
    exec ${python}/bin/python3 ${./linkd/miracast_linkd.py} "$@"
  '';

  # busybox udhcpc script: applies the lease the TV (the P2P group owner) hands
  # out and records it for miracast-linkd. Deliberately no default route and no
  # DNS: this link only carries the stream to the TV.
  dhcpScript = pkgs.writeShellScript "miracast-udhcpc-script" ''
    # udhcpc passes the lease in $ip, $mask, $router, $serverid, ... so the
    # iproute2 binary must not be called "ip".
    iproute=${pkgs.iproute2}/bin/ip
    case "$1" in
      deconfig)
        $iproute -4 addr flush dev "$interface"
        $iproute link set dev "$interface" up
        ;;
      bound|renew)
        $iproute -4 addr flush dev "$interface"
        $iproute -4 addr add "$ip/$mask" broadcast "''${broadcast:-+}" dev "$interface"
        printf '{"ip":"%s","mask":"%s","router":"%s","serverid":"%s"}\n' \
          "$ip" "$mask" "''${router%% *}" "$serverid" > ${cfg.runtimeDir}/lease-"$interface".json.tmp
        mv ${cfg.runtimeDir}/lease-"$interface".json.tmp ${cfg.runtimeDir}/lease-"$interface".json
        ;;
    esac
  '';

  # GStreamer for the source engine. The core elements live in gstreamer's `out`
  # output, the encoder (x264enc) in -ugly, mpegtsmux in -bad.
  gstPlugins = with pkgs.gst_all_1; [
    (lib.getLib gstreamer)
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    pkgs.pipewire
  ];

  # The source engine (user-level; started on demand by `coel-miracast cast`).
  engine = pkgs.writeShellScript "miracast-source" ''
    export PATH=${lib.makeBinPath [ pkgs.gst_all_1.gstreamer.bin ]}:$PATH
    export GST_PLUGIN_SYSTEM_PATH_1_0=${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}
    export PYTHONPATH=${../castlib}''${PYTHONPATH:+:$PYTHONPATH}
    exec ${python}/bin/python3 ${./engine}/miracast_source.py "$@"
  '';

  profilesFile = pkgs.writeText "miracast-profiles.json" (builtins.toJSON cfg.sinkProfiles);

  # Stdlib-only client; deliberately a separate package from the daemon.
  ctl = pkgs.writeShellScriptBin "coel-miracast" ''
    export MIRACAST_STATE=${lib.escapeShellArg "${cfg.runtimeDir}/state.json"}
    export MIRACAST_SOCKET=${lib.escapeShellArg "${cfg.runtimeDir}/linkd.sock"}
    export MIRACAST_ENGINE=${engine}
    ${lib.optionalString (cfg.sinkProfiles != { }) "export MIRACAST_PROFILES=${profilesFile}"}
    export MIRACAST_SYSTEMD_RUN=${pkgs.systemd}/bin/systemd-run
    export MIRACAST_SYSTEMCTL=${pkgs.systemd}/bin/systemctl
    export MIRACAST_JOURNALCTL=${pkgs.systemd}/bin/journalctl
    exec ${pkgs.python3}/bin/python3 ${./ctl/miracast_ctl.py} "$@"
  '';
in
{
  options.services.miracast = {
    enable = lib.mkEnableOption "the Miracast link daemon (Wi-Fi Direct discovery and connection)";

    interface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "wlp1s0";
      description = ''
        wpa_supplicant interface to run Wi-Fi Direct on. `null` picks the first
        interface that exposes the P2P API.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group allowed to use the daemon's control socket.";
    };

    runtimeDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/miracast";
      readOnly = true;
      description = "Where the state file and control socket live (the `miracast` RuntimeDirectory).";
    };

    deviceName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Wi-Fi Direct device name shown on the TV while connecting.";
    };

    scanSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "How long a scan runs when the client doesn't say.";
    };

    peerTtl = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = "Seconds before a device that hasn't been seen is dropped from the list.";
    };

    rtspPort = lib.mkOption {
      type = lib.types.port;
      default = 7236;
      description = ''
        RTSP control port advertised to sinks. The sink connects *to us* on this
        port after the Wi-Fi Direct link is up, so it must be reachable on the
        P2P interface (see `openFirewall`).
      '';
    };

    keepStationAutoconnect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Never let NetworkManager give up reconnecting to Wi-Fi. A Wi-Fi Direct group on a
        different channel than the access point knocks the normal connection off; after
        NetworkManager's default 4 failed attempts it stops auto-connecting until reboot.
        This raises NetworkManager's default retry count (autoconnect-retries-default) from 4 to 100.
      '';
    };

    sinkProfiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          match = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = ''
              Conditions, ANDed. Each value is a case-insensitive regular expression searched in the field:
              name, manufacturer, model, device_type (Wi-Fi Direct peer record), content_protection,
              audio_codecs (what the display advertises). Empty = matches every display.
            '';
          };
          settings = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
            description = ''
              Engine options (argparse names, e.g. vbv_ms, bitrate, preset, audio_start_delay_ms,
              audio_preference, preference, color) applied when the profile matches, unless the same option
              was given on the command line.
            '';
          };
        };
      });
      default = { };
      example = lib.literalExpression ''
        {
          bedroom-tv = {
            match = { name = "bedroom"; };
            settings = { bitrate = 8000; audio_preference = "AAC,LPCM"; };
          };
        }
      '';
      description = ''
        Per-display quirk profiles, as data (see modules/miracast/engine/profiles.py). Written to a JSON file that
        `coel-miracast cast` hands to the engine; matched against the display after its capabilities are known.
        User profiles are tried before the built-in ones (roku, fire-tv); the first match wins.
      '';
    };

    unmanageP2pInNetworkManager = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Tell NetworkManager to leave `p2p-*` interfaces alone. Otherwise it also
        runs its own Wi-Fi Direct scan on the same radio, which makes
        wpa_supplicant reject ours ("scan trigger already pending"), and it
        tries to configure the group interface when a link comes up.
      '';
    };

    protectWpaSupplicantFromP2pInterfaces = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        NixOS ships a udev rule (from `networking.wireless`, which
        NetworkManager turns on) that runs `systemctl try-restart
        wpa_supplicant` whenever *any* Wi-Fi network interface is added or
        removed. A Wi-Fi Direct link creates and later removes a `p2p-*`
        interface of exactly that kind, so every connection attempt restarted
        wpa_supplicant (twice) and dropped the normal Wi-Fi connection.

        That rule only exists while `networking.wireless.interfaces` is empty.
        Setting it to the single Wi-Fi interface removes the rule (and starts
        wpa_supplicant for that interface, which NetworkManager then drives as
        before). Requires `interface` to be set. (udev has no way left to
        cancel or exclude a rule from another file: `last_rule`, `RUN-=` and
        setting `DEVTYPE` were all removed.)
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open `rtspPort` in NixOS's own firewall. Left off by default because
        this machine's firewall setup is managed elsewhere (firewalld + nftables
        in configuration.nix); open the port there for the `p2p-*` interfaces.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.miracast-linkd = {
      description = "Miracast Wi-Fi Direct link daemon";
      wantedBy = [ "multi-user.target" ];
      after = wpaUnits ++ [ "NetworkManager.service" ];
      wants = wpaUnits;
      serviceConfig = {
        ExecStart = lib.escapeShellArgs (
          [
            "${linkd}"
            "--state-file" "${cfg.runtimeDir}/state.json"
            "--socket" "${cfg.runtimeDir}/linkd.sock"
            "--group" cfg.group
            "--peer-ttl" (toString cfg.peerTtl)
            "--scan-seconds" (toString cfg.scanSeconds)
            "--rtsp-port" (toString cfg.rtspPort)
          ]
          ++ lib.optionals (cfg.interface != null) [ "--interface" cfg.interface ]
          ++ lib.optionals (cfg.deviceName != null) [ "--device-name" cfg.deviceName ]
        );
        RuntimeDirectory = "miracast";
        RuntimeDirectoryMode = "0755";
        Restart = "on-failure";
        RestartSec = 3;
        # Needs the system bus (wpa_supplicant's API is root-only) and nothing else.
        # Membership of `group` is what lets it hand the control socket to that
        # group without CAP_CHOWN.
        SupplementaryGroups = [ cfg.group ];
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
      };
    };

    # One instance per group interface (miracast-dhcp@p2p-wlp1s0-N), started and
    # stopped by miracast-linkd over the system bus.
    systemd.services."miracast-dhcp@" = {
      # %i, not %I: %I unescapes the instance name and turns every "-" in an
      # interface name like p2p-wlp1s0-3 into "/".
      description = "DHCP client for the Miracast Wi-Fi Direct group %i";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.busybox}/bin/udhcpc -i %i -n -q -t 10 -T 1 -s ${dhcpScript}";
        ExecStopPost = "${pkgs.iproute2}/bin/ip -4 addr flush dev %i";
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.runtimeDir ];
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_NETLINK" "AF_PACKET" ];
        RestrictNamespaces = true;
        LockPersonality = true;
      };
    };

    environment.systemPackages = [ ctl ];

    # See `protectWpaSupplicantFromP2pInterfaces`.
    networking.wireless.interfaces =
      lib.mkIf cfg.protectWpaSupplicantFromP2pInterfaces [ cfg.interface ];

    assertions = [
      {
        assertion = !cfg.protectWpaSupplicantFromP2pInterfaces || cfg.interface != null;
        message = ''
          services.miracast.protectWpaSupplicantFromP2pInterfaces needs
          services.miracast.interface (the Wi-Fi interface to pin wpa_supplicant to).
        '';
      }
    ];

    networking.networkmanager.settings.main = lib.mkIf cfg.keepStationAutoconnect {
      # profiles with connection.autoconnect-retries = -1 (the default) use this instead of 4
      autoconnect-retries-default = 100;
    };

    networking.networkmanager.unmanaged =
      lib.mkIf cfg.unmanageP2pInNetworkManager [ "interface-name:p2p-*" ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.rtspPort ];
  };
}

{ config, lib, pkgs, options, ... }:

# A guest account whose every change is undone at logout.
#
#   - Home is a tmpfs (RAM): nothing the guest does ever reaches the disk, and
#     it is empty after a reboot.
#   - When the guest's last session ends, coel-guest-reset wipes the home and
#     puts the profile back (home-manager re-runs), so the next guest starts
#     from the same clean desktop.
#   - No password, but only through the login screen (greetd allows an empty
#     password; the console, ssh, sudo and the screen-lock PAM services do not).
#   - Not an admin, not in Nix's allowed users, no GlobalProtect/VPN traffic,
#     no changing the machine's networking, and no way into other accounts'
#     homes (they are 0700).
#
# Pairs with modules/session-hub.nix: the guest is a second account, so it can
# run next to yours (its own session on its own VT) without any of the
# one-account-two-sessions conflicts. One session per account is enforced by
# the hub.
#
# Off by default.

let
  cfg = config.services.coel-guest;
  # A constant, not an option: it is used as an attribute name (users.users.guest,
  # home-manager.users.guest, ...) and the module system needs those before it
  # can evaluate any option value. coel-hub expects the same name.
  user = "guest";
  home = "/home/${user}";
  uid = toString cfg.uid;

  # Puts the profile into the (empty) tmpfs home. Done directly, as root, NOT by
  # running home-manager's activation: that registers its generation with the
  # Nix daemon (nix-store --realise --add-root), which the guest is not allowed
  # to talk to (and a throwaway home needs no GC roots). The profile's files
  # are symlinks into the store, but its directories are read-only store
  # directories, so they are made writable and handed to the guest -- otherwise
  # the guest could not create anything under ~/.config.
  seedScript = pkgs.writeShellScript "coel-guest-seed" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.findutils ]}
    cp -a --no-preserve=mode,ownership ${cfg.seedFrom}/. ${home}/
    find ${home} -type d -exec chmod u+rwx {} +
    chown -R --no-dereference ${user}:${user} ${home}
  '';

  resetScript = pkgs.writeShellScript "coel-guest-reset" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.systemd pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.procps ]}
    CLEAN=/run/coel-guest/clean

    # A guest session that is still up means: nothing to do.
    in_use() {
      for f in /run/systemd/sessions/*; do
        [ -f "$f" ] || continue
        if grep -qx "USER=${user}" "$f" && grep -qx "CLASS=user" "$f"; then
          return 0
        fi
      done
      return 1
    }

    # Seen in use: remember it, so the logout that follows is not skipped as
    # "already clean". (Every session change runs this, so a login is noticed.)
    if in_use; then
      rm -f "$CLEAN"
      exit 0
    fi
    # Wiped already and nobody has logged in since: nothing to do.
    [ -e "$CLEAN" ] && exit 0

    # Finish the account: its user manager lingers a few seconds after the
    # last session, and a leftover process would keep files open.
    loginctl terminate-user ${user} 2>/dev/null || true
    for _ in $(seq 1 60); do
      if ! systemctl is-active --quiet "user@${uid}.service" && [ ! -d /run/user/${uid} ]; then
        break
      fi
      sleep 0.5
    done
    pkill -KILL -u ${user} 2>/dev/null || true

    # Somebody logged in again while we waited: leave it alone.
    in_use && exit 0

    find ${home} -mindepth 1 -delete
    find /tmp /var/tmp -xdev -user ${user} -delete 2>/dev/null || true
    ${lib.optionalString (cfg.seedFrom != null) "${seedScript}"}
    mkdir -p /run/coel-guest
    touch "$CLEAN"
  '';
in
{
  options.services.coel-guest = {
    enable = lib.mkEnableOption "a guest account that is wiped when it logs out";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1100;
      description = "Fixed uid/gid (the tmpfs home is mounted with it).";
    };

    tmpfsSize = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = "Size cap of the guest's RAM-backed home (counts against memory only while used).";
    };

    homeModule = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = ../home/guest.nix;
      description = "home-manager profile for the guest (null: none).";
    };

    seedFrom = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        A directory whose contents become the guest's home at boot and after
        every wipe (set automatically from the home-manager profile when there
        is one).
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
  {
    users.groups.${user}.gid = cfg.uid;
    users.users.${user} = {
      isNormalUser = true;
      uid = cfg.uid;
      group = user;
      description = "Guest";
      inherit home;
      createHome = false; # the home is a tmpfs, mounted below
      extraGroups = [ ]; # no wheel, no networkmanager, no globalprotect
      # Empty password. Only the services that opt in (greetd, which the login
      # screen uses) accept it; sudo, su, ssh, login and the lock-screen PAM
      # stacks keep refusing empty passwords.
      hashedPassword = "";
    };

    fileSystems.${home} = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "x-mount.mkdir"
        "mode=0700"
        "uid=${uid}"
        "gid=${uid}"
        "size=${cfg.tmpfsSize}"
        "nosuid"
        "nodev"
      ];
    };

    # NixOS lets the console login (getty on VT2-6) accept an EMPTY password by
    # default. With the guest that would be a text login for anyone, so turn it
    # off: the guest gets in only through the login screen (greetd, which
    # allows it). Every real account has a password, so nothing else changes.
    security.pam.services.login.allowNullPassword = lib.mkForce false;

    # Guests do not get to run Nix builds through the daemon.
    nix.settings.allowed-users = [ "root" "@wheel" ];

    # No VPN: nothing the guest sends may leave through a tunnel interface
    # (GlobalProtect's is gpd0), even while you are connected.
    networking.nftables.tables.coel-guest = {
      family = "inet";
      content = ''
        chain output {
          type filter hook output priority filter; policy accept;
          meta skuid ${uid} oifname "gpd0" reject
          meta skuid ${uid} oifname "tun*" reject
          meta skuid ${uid} oifname "wg*" reject
          meta skuid ${uid} oifname "proton*" reject
        }
      '';
    };

    # No changing the machine's networking: no saving or editing connections,
    # switching Wi-Fi off, etc. The guest uses whatever network is up.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (subject.user == "${user}" &&
            action.id.indexOf("org.freedesktop.NetworkManager.") == 0) {
          return polkit.Result.NO;
        }
      });
    '';

    # At boot the tmpfs home is empty and freshly seeded: that is "clean", so
    # the first session change of the day must not wipe it again.
    systemd.tmpfiles.rules = [
      "d /run/coel-guest 0755 root root -"
      "f /run/coel-guest/clean 0644 root root -"
    ];

    systemd.services.coel-guest-reset = {
      description = "Wipe the guest account once nobody is logged in as it";
      # Session changes can come in bursts (boot, a login); each one starts
      # this. systemd's default start limit (5 starts in 10s) would trip and
      # then disable the service AND its path unit for good -- the guest would
      # silently never be wiped again. It exits at once when there is nothing to do.
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = resetScript;
        TimeoutStartSec = 120;
      };
    };
    # Runs whenever a session appears or disappears (nothing is polled).
    systemd.paths.coel-guest-reset = {
      description = "Look for a finished guest session";
      unitConfig.StartLimitIntervalSec = 0;
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = "/run/systemd/sessions";
        Unit = "coel-guest-reset.service";
      };
    };

  }

  # The home-manager profile, when home-manager is part of the system (it is
  # not in the headless VM test).
  (lib.optionalAttrs (options ? home-manager) {
    home-manager.users.${user} = lib.mkIf (cfg.homeModule != null) (import cfg.homeModule);
    # Seeded by coel-guest-seed instead (see seedScript): home-manager's own
    # activation needs the Nix daemon, which the guest may not use.
    systemd.services."home-manager-${user}".enable = lib.mkIf (cfg.homeModule != null) false;
    services.coel-guest.seedFrom = lib.mkIf (cfg.homeModule != null)
      "${config.home-manager.users.${user}.home.activationPackage}/home-files";
  })

  # Put the profile in at boot too (the tmpfs starts empty).
  (lib.mkIf (cfg.seedFrom != null) {
    systemd.services.coel-guest-seed = {
      description = "Put the guest's profile into its RAM home";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = home;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = seedScript;
      };
    };
  })
  ]);
}

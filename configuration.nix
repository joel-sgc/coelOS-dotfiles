{
  config,
  pkgs,
  pkgs-unstable,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/kdeconnect.nix
    ./modules/globalprotect.nix
    ./modules/nix-ld.nix
    ./modules/filesystems.nix
  ];

  ##############################################################################
  # Boot / Bootloader
  ##############################################################################

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 0;

  boot.kernelParams = [
    "quiet"
    "splash"
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];

  boot.plymouth = {
    enable = true;
    theme = "coelos";
    themePackages = [
      (pkgs.stdenv.mkDerivation {
        pname = "coelos-plymouth-theme";
        version = "1.0";
        # Points to the folder containing the CoelOS theme files
        src = ./coelos-theme;

        installPhase = ''
          mkdir -p $out/share/plymouth/themes/coelos
          cp * $out/share/plymouth/themes/coelos/

          sed -i "s@^ImageDir=.*@ImageDir=$out/share/plymouth/themes/coelos@" $out/share/plymouth/themes/coelos/coelos.plymouth
          sed -i "s@^ScriptFile=.*@ScriptFile=$out/share/plymouth/themes/coelos/coelos.script@" $out/share/plymouth/themes/coelos/coelos.plymouth
        '';
      })
    ];
  };

  ##############################################################################
  # Networking
  ##############################################################################

  networking.hostName = "coelos";
  networking.networkmanager.enable = true;
  networking.firewall.checkReversePath = false; # Needed for ProtonVPN

  # See globalprotect-hip-investigation.md for the LUC HIP-compliance
  # investigation this nftables/firewalld choice (and the commented-out
  # iptables-legacy line below) came out of.
  # networking.firewall.package = pkgs.iptables-legacy;
  networking.nftables.enable = true;
  services.firewalld.enable = true;

  # Split-horizon DNS: Cloudflare as the general-purpose resolver, while
  # Tailscale's *.ts.net names and (if/when GlobalProtect ever pushes any)
  # LUC-internal names get scoped to their own resolvers instead of a
  # strict try-everything-in-order chain -- a flat priority list would mean
  # internal names only resolve after the earlier resolvers fail/time out,
  # which is backwards for domains a generic public resolver never knows
  # about anyway.
  #
  # enabling this handles the NetworkManager/resolvconf wiring itself
  # (nixos/modules/system/boot/resolved.nix sets
  # networking.networkmanager.dns = "systemd-resolved" and switches
  # networking.resolvconf.package to systemd's own resolvconf-compatible
  # shim automatically) -- GlobalProtect's `resolvconf -a` calls keep
  # working unchanged, just properly captured as gpd0's per-link DNS in
  # resolved instead of overwriting /etc/resolv.conf directly. Tailscale
  # auto-detects resolved and registers its own ts.net-scoped DNS the same
  # way, no extra config needed. DHCP-provided network DNS still becomes
  # wlp1s0's per-link DNS as before, so it's still in the resolver pool as
  # a fallback if Cloudflare is unreachable (e.g. a captive portal) --
  # just not as a hardcoded, network-specific address, since that changes
  # every time the laptop joins a different network.
  services.resolved = {
    enable = true;
    settings.Resolve.DNS = [
      "1.1.1.1"
      "1.0.0.1"
    ];
  };

  # Terminal-friendly NetworkManager TUI (github:joel-sgc/netpala). Configured
  # via its Home Manager module + modules/netpala.nix, both imported from
  # home.nix -- see there, not here.

  # Tailscale
  services.tailscale.enable = true;
  # Lets joelsgc run `tailscale up/down/set/...` without sudo. Applied via a
  # oneshot systemd unit (tailscaled-set, from the tailscale module itself)
  # that runs `tailscale set --operator=joelsgc` automatically after every
  # boot -- equivalent to running that command by hand, just declarative.
  services.tailscale.extraSetFlags = [
    "--operator=joelsgc"
    "--accept-routes"
    "--ssh"
  ];
  networking.firewall.allowedUDPPorts = [ 41641 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Personal server sshfs mount
  programs.fuse.userAllowOther = true;
  fileSystems."/home/joelsgc/server" = {
    device = "joel@jsgc-server:/files";
    fsType = "fuse.sshfs";
    options = [
      "x-systemd.automount"
      "_netdev"
      "port=2222"
      "IdentityFile=/home/joelsgc/.ssh/id_ed25519_coelos_server"
      "IdentitiesOnly=yes"
      "StrictHostKeyChecking=accept-new"
      "allow_other"
      "uid=1000"
      "gid=100"
      "reconnect"
      "ServerAliveInterval=15"
      "ServerAliveCountMax=3"
    ];
  };

  ##############################################################################
  # Desktop Environment
  ##############################################################################

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Hyprland, added alongside Plasma as a second selectable SDDM session
  # while migrating. Phase 1: bare compositor only — portals, bars, and
  # the rest of the tray/applet stack land in later phases.
  programs.hyprland.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.excludePackages = [ pkgs.xterm ];

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
    elisa
    kwallet
    kwalletmanager
    kate
  ];

  # Linking Ghostty to DBus
  services.dbus.packages = [ pkgs.ghostty ];

  # Keyring (GNOME Keyring for Secret Service / credentials in VS Code, etc.)
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  # Required for hyprlock to actually authenticate (Hyprland's lock screen,
  # separate from Plasma's own kscreenlocker/PAM service).
  #
  # fprintAuth explicitly disabled here even though services.fprintd.enable
  # would otherwise default it to true: hyprlock has its own independent
  # native fingerprint backend (home/hypridle.nix's `auth.fingerprint.enabled`,
  # confirmed straight from hyprlock's src/auth/Auth.cpp -- CPam and
  # CFingerprint are two separate implementations, either succeeding
  # unlocks). Leaving pam_fprintd.so *also* in this PAM stack made it
  # redundant -- worse, since pam_fprintd is `sufficient` and listed before
  # pam_unix, it blocked *this* conversation's password check until its own
  # fingerprint attempt resolved, which is exactly what made typing a
  # password and pressing enter feel like it also required a fingerprint
  # scan. Native hyprlock fingerprint auth genuinely runs in parallel
  # instead of nesting inside the password conversation.
  security.pam.services.hyprlock.fprintAuth = false;

  # SDDM (the login screen) had the same "feels like it needs both a password
  # AND a fingerprint" symptom as hyprlock did before the fix above -- but
  # the fix itself has to be different. Confirmed from /etc/pam.d/sddm: SDDM
  # doesn't get its own generated PAM stack at all, it's `auth substack
  # login`, so this is really about /etc/pam.d/login. Unlike hyprlock, login
  # (and therefore SDDM) has no independent native fingerprint path to fall
  # back on -- pam_fprintd.so is the *only* way it can check a fingerprint,
  # so disabling fprintAuth here (hyprlock's fix) would remove fingerprint
  # login from the greeter entirely, not just stop it from blocking the
  # password field.
  #
  # Instead: pam_fprintd.so is `sufficient` and was ordered *before*
  # pam_unix.so (order 11400 vs 12900, confirmed from the generated file),
  # so typing a password and hitting enter had to wait for the fingerprint
  # module's own conversation to resolve first -- same root cause as
  # hyprlock, just fixed by reordering instead of disabling. Moving it to
  # just after the real password check (`unix`, not the earlier
  # `likeauth`-only `unix-early`) means: typing a password authenticates
  # immediately without ever reaching pam_fprintd, and a fingerprint scan
  # with no password typed still falls through unix's (fast, non-blocking)
  # failure to reach pam_fprintd and succeed on its own -- fingerprint alone
  # is sufficient either way, matching hyprlock's actual behavior even
  # though the mechanism differs. Set as a relative offset from `unix`'s own
  # order per the option's own documented guidance, since the absolute
  # values are that module's internal implementation detail and could shift
  # on a nixpkgs update.
  security.pam.services.login.rules.auth.fprintd.order =
    config.security.pam.services.login.rules.auth.unix.order + 10;

  # Grants the `video` group write access to /sys/class/backlight so swayosd
  # (Hyprland session's volume/brightness OSD) can adjust brightness without
  # running as root.
  services.udev.packages = [ pkgs.swayosd ];

  # XDG Portals
  #
  # Per-desktop backend selection instead of a flat wildcard default, so
  # screen sharing / file pickers / etc. resolve to the *actual* running
  # session's backend rather than whichever portal implementation happens
  # to be found first. Matched against $XDG_CURRENT_DESKTOP (case-insensitive):
  # Hyprland sets "Hyprland", Plasma sets "KDE".
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      hyprland.default = [
        "hyprland"
        "gtk"
      ];
      kde.default = [ "kde" ];
      common.default = [ "gtk" ];
    };
  };

  ##############################################################################
  # Hardware
  ##############################################################################

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  # services.blueman.enable = true; # Optional GUI Bluetooth manager

  # Backs the power-profile switcher in the ported rofi settings menu
  # (powerprofilesctl) — see home/rofi.nix.
  services.power-profiles-daemon.enable = true;

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # jack.enable = true; # Uncomment for JACK applications
  };

  services.libinput.enable = true;
  services.libinput.touchpad.naturalScrolling = true;
  services.fprintd.enable = true;

  # Lets the wheel group enroll fingerprints without the enroll-itself-
  # needs-auth chicken/egg problem (enrolling normally requires an already-
  # authenticated session, which is circular the first time). Ported from
  # the old dotfiles' configs/polkit-fprint.rules.
  security.polkit.extraConfig = builtins.readFile ./configuration/polkit-fprint-enroll.js;

  # Lid-close behavior, ported from the old dotfiles' configs/power/logind-power.conf.
  # Deliberately suspends even on AC power (not the usual NixOS/systemd
  # default, which normally ignores lid-close while plugged in) -- matches
  # what was explicitly set up before. Power-key handling is intentionally
  # not touched here: it's already covered separately, but only within the
  # Hyprland session (see the systemd-inhibit + coel-power-menu bind in
  # home/hyprland.nix) -- under Plasma, the physical power key still uses
  # whatever systemd's own default is.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  ##############################################################################
  # Users & Shell
  ##############################################################################

  nix.settings.trusted-users = [
    "root"
    "@wheel"
    "joelsgc"
  ];
  users.users."joelsgc" = {
    isNormalUser = true;
    description = "JoelSGC";
    extraGroups = [
      "networkmanager"
      "wheel"
      "globalprotect"
      "video"
      "libvirtd" # manage VMs without sudo -- see Virtualisation section
      "dialout"
    ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  ##############################################################################
  # Filesystem Support (HFS+ / APFS / NTFS / exFAT)
  #
  # Toggles the userspace tools (mkfs.*, fsck.*, apfs-fuse) from
  # modules/filesystems.nix -- kernel-level read/write mount support for
  # all four stays on regardless of these. All disabled for now since none
  # of the external-drive work is currently active; flip back to true
  # per-filesystem whenever that tooling is needed again.
  ##############################################################################

  filesystemSupport = {
    ntfs.extraTools = true;
    hfs.extraTools = false;
    apfs.extraTools = false;
    exfat.extraTools = false;
  };

  ##############################################################################
  # System Packages & Nix Settings
  ##############################################################################

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = [
    pkgs.micro
    pkgs.git
    pkgs.sshfs

    # Basic CLI utilities NixOS doesn't ship by default (unlike most
    # distros' base install)
    pkgs.file
    pkgs.tree
    pkgs.binutils-unwrapped # strings, nm, objdump, readelf, etc.
    pkgs.unzip
    pkgs.zip
    pkgs.which
    pkgs.lsof
    pkgs.psmisc # killall, pstree, fuser
    pkgs.pciutils # lspci
    pkgs.usbutils # lsusb
    pkgs.dnsutils # dig, nslookup, host
    pkgs.btop
    pkgs.ripgrep
    pkgs.fd
    pkgs.ncdu
    pkgs.jq

    pkgs.vlc

    # VS Code's jnoortheen.nix-ide extension talks to these -- LSP +
    # semantic highlighting/diagnostics, and format-on-save, for .nix files.
    pkgs.nixd
    pkgs.nixfmt
    pkgs.dmidecode
    
    # Freecad from unstable
    pkgs-unstable.freecad
  ];
  
  services.flatpak.enable = true;

  ##############################################################################
  # Virtualisation
  ##############################################################################

  # For testing GlobalProtect's HIP compliance detection on a real .deb/.rpm
  # target (Palo Alto's Linux client is only actually built/tested for
  # those) -- to check whether the empty anti-malware/firewall detection
  # (see globalprotect-hip-investigation.md) is a NixOS/vendoring quirk or
  # a genuine cross-distro OPSWAT Linux limitation.
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  programs.virt-manager.enable = true;
  
  services.udev.extraRules = ''
    KERNEL=="sda", GROUP="kvm", MODE="0660"
  '';

  ##############################################################################
  # Other Services
  ##############################################################################

  services.openssh.enable = true;

  programs.firefox.enable = false;

  ##############################################################################
  # Locale / Time
  ##############################################################################

  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  ##############################################################################
  # State Version
  ##############################################################################

  # This value determines the NixOS release from which the default settings
  # for stateful data, like file locations and database versions, were taken.
  # Leave this at the release version of the first install of this system.
  system.stateVersion = "26.05";
}

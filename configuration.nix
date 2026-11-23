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
    ./modules/greeter.nix
    ./modules/session-hub.nix
    ./modules/guest.nix
    ./modules/tty.nix
    ./modules/fnlock/nixos/fnlock.nix
    ./modules/miracast
    ./modules/gcast
    # On trial (started Oct 2026): returns the EC to the patched RW firmware at
    # boot after an EC reset. Each jump is an unclean power-off that counts
    # toward the TPM lockout limit -- see modules/fnlock/README.md. Remove this
    # line to turn it off; the service is a no-op while the EC is already on RW.
    ./modules/fnlock/nixos/ec-jump-rw.nix
  ];

  # The Quickshell/greetd login screen (modules/greeter.nix is a no-op
  # until this is set).
  services.qs-greeter.enable = true;

  # The login screen stays on VT1 and is also the lock screen; sessions run on
  # their own VTs (7, 8) behind it. Locking (Super+L, the menus, the idle timer)
  # goes to the login screen, and coming back means signing in there. See
  # modules/session-hub.nix. Needs services.qs-greeter above (that is the
  # login screen); to switch back to the plain login, remove this line.
  services.coel-hub.enable = true;

  # A guest account (login screen: "guest", no password) whose home lives in RAM
  # and is wiped when it logs out. Not an admin, no Nix builds, no VPN, no
  # network changes. See modules/guest.nix and home/guest.nix.
  services.coel-guest.enable = true;

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
        src = ./assets/plymouth-theme;

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

  # nftables/firewalld chosen over iptables-legacy per the LUC HIP-compliance
  # investigation (modules/globalprotect/globalprotect-hip-investigation.md).
  # networking.firewall.package = pkgs.iptables-legacy;
  networking.nftables.enable = true;
  services.firewalld.enable = true;

  # systemd-resolved for split-horizon DNS: Cloudflare as the general
  # resolver, while Tailscale's *.ts.net names and any LUC-internal names
  # GlobalProtect pushes get scoped to their own per-link resolvers instead
  # of a flat try-in-order chain. Enabling this also wires NetworkManager/
  # resolvconf to resolved automatically, so GlobalProtect's `resolvconf -a`
  # calls and Tailscale's own DNS registration keep working unchanged.
  services.resolved = {
    enable = true;
    settings.Resolve.DNS = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    # Avahi (below) does the mDNS browsing for casting; resolved's own mDNS
    # would fight it over udp 5353 and also announces this host on every
    # network, campus wifi included.
    settings.Resolve.MulticastDNS = "no";
  };

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
    "--exit-node=100.98.151.60" # jsgc-server; a MagicDNS name or the node ID also works
    "--exit-node-allow-lan-access"
  ];
  networking.firewall.allowedUDPPorts = [ 41641 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # mDNS browsing for casting (Chromecast/AirPlay discovery, used by
  # gnome-network-displays and coel-cast-scan). Browse only: nothing about
  # this machine is announced on the network (publish off) -- matters on
  # shared campus wifi. openFirewall opens udp 5353 for the replies.
  services.avahi = {
    enable = true;
    openFirewall = true;
    publish.enable = false;
    nssmdns4 = false;
  };
  # Miracast (Wi-Fi Direct): the TV connects back to the source's RTSP
  # control port.
  networking.firewall.allowedTCPPorts = [ 7236 ];
  # Miracast discovery/link daemon (modules/miracast, see its README.md).
  services.miracast.enable = true;
  services.miracast.interface = "wlp1s0";

  # Google Cast sender (modules/gcast, see its README.md): coel-gcast scan / cast / stop.
  services.gcast.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Personal server sshfs mount
  programs.fuse.userAllowOther = true;
  # The server mount itself is a user service, not a fileSystems entry: see
  # home/server-mount.nix (an fstab/automount entry leaves a ghost directory
  # and stalls anything that stats ~/server while the server is down).

  ##############################################################################
  # Desktop Environment
  ##############################################################################

  services.xserver.enable = true;

  # Services the Plasma module used to enable implicitly: udiskie
  # (home/udiskie.nix) and Dolphin's device handling need udisks2, and
  # battery/power data (poweralertd, the Quickshell panel) comes from UPower.
  services.udisks2.enable = true;
  services.upower.enable = true;

  # The USB-C hub dongle (VIA hub 2109:0817 + Realtek r8152 Ethernet + card
  # reader) on xhci 0000:c3:00.3 reset itself every ~10 s the moment the Ethernet
  # link carried traffic (kernel: "Tx status -71", then "usb 6-1: reset
  # SuperSpeed USB device"), which kept dropping the shared connection to the
  # Raspberry Pi. Turning USB3 link power management (U1/U2) off on that
  # controller's ports stopped it. Glob so it does not depend on the bus number.
  systemd.tmpfiles.rules = [
    "w /sys/bus/pci/devices/0000:c3:00.3/usb*/*-0:1.0/usb*-port*/usb3_lpm_permit - - - - 0"
  ];

  # The Plasma module also supplied the system fonts and default families;
  # without them GTK/wx apps (OrcaSlicer, ...) fall back to DejaVu and
  # render missing glyphs as boxes.
  fonts.packages = [
    pkgs.noto-fonts
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-color-emoji
    pkgs.hack-font
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = [
      "Hack"
      "Noto Sans Mono"
    ];
    sansSerif = [ "Noto Sans" ];
    serif = [ "Noto Serif" ];
  };

  programs.hyprland = {
    enable = true;
    # Launch through UWSM: Hyprland runs as wayland-wm@*.service and the
    # session gets a real graphical-session.target / env import / cgroups.
    withUWSM = true;
    # Hyprland with the grid-aware three-finger swipe (see the patch's header and
    # TODO.md). Re-check the patch after every Hyprland update.
    package = pkgs.hyprland.overrideAttrs (o: {
      patches = (o.patches or [ ]) ++ [ ./patches/hyprland-grid-swipe.patch ];
    });
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.excludePackages = [ pkgs.xterm ];

  # Linking Ghostty to DBus
  services.dbus.packages = [ pkgs.ghostty ];

  # Keyring (GNOME Keyring for Secret Service / credentials in VS Code, etc.)
  services.gnome.gnome-keyring.enable = true;

  # Required for hyprlock to authenticate. fprintAuth disabled here even
  # though fprintd.enable would default it to true: hyprlock has its own
  # independent native fingerprint backend (auth.fingerprint.enabled in
  # home/hypridle.nix; CPam/CFingerprint are separate, either succeeding
  # unlocks). Leaving pam_fprintd.so in this stack too was redundant and
  # actively wrong -- as a `sufficient` module listed before pam_unix, it
  # blocked the password check until its own fingerprint attempt resolved,
  # making a typed password feel like it needed a fingerprint scan too.
  security.pam.services.hyprlock.fprintAuth = false;

  # /etc/pam.d/login has the same "password waits on fingerprint" symptom
  # as hyprlock, but no independent native fingerprint path to fall back
  # on -- pam_fprintd is the only way it can check a fingerprint, so
  # disabling it here would remove fingerprint login entirely rather than
  # just unblocking the password field. Fix instead: reorder pam_fprintd to run just after the
  # real password check (`unix`), not before it, so a typed password
  # authenticates immediately and a lone fingerprint scan still falls
  # through unix's fast failure to reach pam_fprintd. Set as an offset from
  # unix's own order per the option's documented guidance, since the
  # absolute values are nixpkgs' internal detail.
  security.pam.services.login.rules.auth.fprintd.order =
    config.security.pam.services.login.rules.auth.unix.order + 10;

  # Auth backend for the Quickshell lock screen (home/quickshell/lock/,
  # replacing hyprlock -- see home/hypridle.nix for why hyprlock's config
  # stays as an unused manual fallback), driven by a native PamContext
  # (Quickshell.Services.Pam) in AuthBackend.qml -- not a `pamtester`
  # subprocess, which an earlier pass wrongly believed was necessary before
  # finding the real native binding. Two single-purpose stacks, not one
  # shared one -- keeps pam_unix and pam_fprintd from ever sharing a stack,
  # sidestepping the same ordering bug fixed above for hyprlock/login.
  security.pam.services.quickshell-lock.fprintAuth = false;
  security.pam.services.quickshell-lock-fp.unixAuth = false;

  # Grants the `video` group write access to /sys/class/backlight -- the
  # swayosd-server binary itself is gone (replaced by
  # home/quickshell/Osd.qml), but this udev rule is still what
  # PowerDropdown.qml's brightness slider and Osd.qml's own brightness
  # control both rely on to write there without running as root. Keeping
  # `pkgs.swayosd` here only as the source of that rule file, not because
  # anything actually runs it anymore.
  # libmtp's rules tag phones/players as MTP devices (ID_MTP_DEVICE,
  # ID_MEDIA_PLAYER). Dolphin's MTP support (kio-extras' kmtpd) only lists
  # devices carrying those tags, so without this an unlocked, working phone
  # never shows up there even though `mtp-detect` can read it.
  services.udev.packages = [ pkgs.swayosd pkgs.libmtp.out ];

  # Per-desktop portal backend selection (matched against
  # $XDG_CURRENT_DESKTOP) instead of a flat default, so screen sharing/file
  # pickers resolve to the actual running session's portal rather than
  # whichever implementation is found first.
  xdg.portal = {
    enable = true;
    # (the hyprland portal is added by programs.hyprland, built against its package)
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      hyprland.default = [
        "hyprland"
        "gtk"
      ];
      common.default = [ "gtk" ];
    };
  };

  ##############################################################################
  # Hardware
  ##############################################################################

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  # services.blueman.enable = true; # Optional GUI Bluetooth manager

  # Backs the power-profile switcher (powerprofilesctl).
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
  security.polkit.extraConfig = builtins.readFile ./scripts/polkit-fprint-enroll.js;

  # Suspends on lid-close even on AC power (systemd's default otherwise
  # ignores lid-close while plugged in). Power-key handling isn't touched
  # here -- Hyprland covers it separately (systemd-inhibit + coel-power-menu
  # in home/hyprland.nix).
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

  # Registers a binfmt_misc handler so `./foo.AppImage` just runs (the
  # kernel hands it to appimage-run automatically) instead of needing
  # `appimage-run ./foo.AppImage` by hand every time.
  programs.appimage = {
    enable = true;
    binfmt = true;
    # Base appimage-run's FHS env doesn't ship WebKitGTK (too big to
    # include by default) -- added for OrcaSlicer-Nonplanar's AppImage,
    # which embeds a webview and needs libwebkit2gtk-4.1.so.0.
    package = pkgs.appimage-run.override {
      extraPkgs = pkgs: [ pkgs.webkitgtk_4_1 ];
    };
  };

  environment.systemPackages = [
    pkgs.framework-tool
    pkgs.micro
    pkgs.git
    pkgs.sshfs
    pkgs.arp-scan

    # Dolphin, no longer pulled in by the Plasma module: kio-extras (sftp://,
    # trash:/, MTP...), kio-fuse (lets non-KDE apps open files from KIO
    # locations), kde-cli-tools (kioclient/"open with" helpers), thumbnailers
    # and breeze-icons as the icon fallback behind Papirus.
    pkgs.kdePackages.dolphin
    pkgs.kdePackages.kio-extras
    pkgs.kdePackages.kio-fuse
    pkgs.kdePackages.kde-cli-tools
    pkgs.kdePackages.ffmpegthumbs
    pkgs.kdePackages.kdegraphics-thumbnailers
    pkgs.kdePackages.breeze-icons

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
    pkgs.ripgrep
    pkgs.fd
    pkgs.ncdu
    pkgs.jq

    pkgs.vlc
    pkgs.ffmpeg

    # VS Code's jnoortheen.nix-ide extension talks to these -- LSP +
    # semantic highlighting/diagnostics, and format-on-save, for .nix files.
    pkgs.nixd
    pkgs.nixfmt
    pkgs.dmidecode

    # Freecad from unstable
    pkgs-unstable.freecad

    # Wireshark
    pkgs.wireshark
  ];

  services.flatpak.enable = true;

  ##############################################################################
  # Virtualisation
  ##############################################################################

  # For testing GlobalProtect's HIP compliance detection on a real .deb/.rpm
  # target (Palo Alto's Linux client is only built/tested for those) -- to
  # check whether the empty anti-malware/firewall detection
  # (modules/globalprotect/globalprotect-hip-investigation.md) is a
  # NixOS/vendoring quirk or a genuine cross-distro OPSWAT limitation.
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.podman.enable = true;

  services.udev.extraRules = ''
    # Dolphin lists both the raw LUKS container partition ("Encrypted Drive",
    # nvme0n1p2/p3) and the unlocked mapping on top of it ("Internal Drive",
    # dm-0/dm-1) -- the same storage twice. Hide the raw containers (matched by
    # the LUKS UUIDs from hardware-configuration.nix) from UDisks/Solid; the
    # unlocked volumes stay visible and nothing about unlocking/mounting changes.
    ENV{ID_FS_TYPE}=="crypto_LUKS", ENV{ID_FS_UUID}=="e5e26cad-5394-4351-a7b4-d2f44f8f4972", ENV{UDISKS_PRESENTATION_HIDE}="1", ENV{UDISKS_IGNORE}="1"
    ENV{ID_FS_TYPE}=="crypto_LUKS", ENV{ID_FS_UUID}=="2ad05545-2e7b-4191-93ad-3f654549bb9d", ENV{UDISKS_PRESENTATION_HIDE}="1", ENV{UDISKS_IGNORE}="1"
    KERNEL=="sda", GROUP="kvm", MODE="0660"

    # The Bluetooth radio keeps ending up soft-blocked for no reason (seen
    # as "Failed to set mode: Failed (0x03)" in bluetoothd), and
    # systemd-rfkill then persists that across reboots. Nothing here
    # soft-blocks it on purpose (the panel toggles adapter power, not
    # rfkill), so clear it whenever it appears.
    SUBSYSTEM=="rfkill", ATTR{type}=="bluetooth", ACTION=="add|change", ATTR{soft}=="1", ATTR{soft}="0"
  '';

  ##############################################################################
  # Gaming
  #
  # Steam itself has to be enabled here, not in home-manager: it needs
  # 32-bit graphics libraries (programs.steam.enable turns on
  # hardware.graphics.enable32Bit for us), controller udev rules, and the
  # FHS/pressure-vessel sandbox, none of which a user profile can provide.
  # Per-game settings (Proton version, launch options, mod files) live in
  # home/steam.nix.
  ##############################################################################

  programs.steam.enable = true;

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

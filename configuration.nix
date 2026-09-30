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
    ./modules/ultraleap.nix
    ./modules/greeter.nix
  ];

  # Flips SDDM -> the Quickshell/greetd login screen (modules/greeter.nix
  # is a no-op until this is set). Use `nixos-rebuild test` only until this
  # is confirmed working on real hardware -- `switch` would make an
  # unconfirmed regression the default boot.
  services.qs-greeter.enable = true;

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
    device = "sftp@jsgc-server:/upload";
    fsType = "fuse.sshfs";
    options = [
      "x-systemd.automount"
      "_netdev"
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
    gwenview
  ];

  # Linking Ghostty to DBus
  services.dbus.packages = [ pkgs.ghostty ];

  # Keyring (GNOME Keyring for Secret Service / credentials in VS Code, etc.)
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  # Required for hyprlock to authenticate. fprintAuth disabled here even
  # though fprintd.enable would default it to true: hyprlock has its own
  # independent native fingerprint backend (auth.fingerprint.enabled in
  # home/hypridle.nix; CPam/CFingerprint are separate, either succeeding
  # unlocks). Leaving pam_fprintd.so in this stack too was redundant and
  # actively wrong -- as a `sufficient` module listed before pam_unix, it
  # blocked the password check until its own fingerprint attempt resolved,
  # making a typed password feel like it needed a fingerprint scan too.
  security.pam.services.hyprlock.fprintAuth = false;

  # SDDM has the same "password waits on fingerprint" symptom as hyprlock,
  # but no independent native fingerprint path to fall back on -- SDDM has
  # no PAM stack of its own (`auth substack login`), and pam_fprintd is the
  # only way /etc/pam.d/login can check a fingerprint, so disabling it here
  # would remove fingerprint login entirely rather than just unblocking the
  # password field. Fix instead: reorder pam_fprintd to run just after the
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

  # Grants the `video` group write access to /sys/class/backlight so swayosd
  # (Hyprland session's volume/brightness OSD) can adjust brightness without
  # running as root.
  services.udev.packages = [ pkgs.swayosd ];

  # Per-desktop portal backend selection (matched against
  # $XDG_CURRENT_DESKTOP) instead of a flat default, so screen sharing/file
  # pickers resolve to the actual running session's portal rather than
  # whichever implementation is found first.
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
  security.polkit.extraConfig = builtins.readFile ./configuration/polkit-fprint-enroll.js;

  # Suspends on lid-close even on AC power (systemd's default otherwise
  # ignores lid-close while plugged in). Power-key handling isn't touched
  # here -- Hyprland covers it separately (systemd-inhibit + coel-power-menu
  # in home/hyprland.nix); under Plasma the physical key uses systemd's own
  # default.
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

  services.udev.extraRules = ''
    KERNEL=="sda", GROUP="kvm", MODE="0660"
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

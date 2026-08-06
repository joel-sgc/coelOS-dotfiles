{ inputs, config, pkgs, lib, ... }:

let
  # Flip this to false to fully disable the ClamAV experiment we added
  # while trying to satisfy LUC's GlobalProtect HIP compliance check.
  # Leaves the actual GlobalProtect packaging (modules/globalprotect.nix)
  # untouched either way.
  enableGpHipComplianceExperiment = false;
in
{
  imports = [
    ./hardware-configuration.nix
    ./modules/kdeconnect.nix
    ./modules/globalprotect.nix
  ];

  ##############################################################################
  # Boot / Bootloader
  ##############################################################################

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 0;

  boot.kernelParams = [ "quiet" "splash" ];
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

  # Tailscale
  services.tailscale.enable = true;
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
  # GlobalProtect HIP compliance experiment (toggleable)
  #
  # Added while trying to satisfy LUC's GlobalProtect firewall/antivirus HIP
  # check. So far it has NOT changed the gateway's compliance verdict, so this
  # is a candidate for full removal once LUC IT responds with what's actually
  # required. Set enableGpHipComplianceExperiment = false above to disable
  # everything in this block without deleting it.
  ##############################################################################

  services.clamav = lib.mkIf enableGpHipComplianceExperiment {
    daemon.enable = true;
    updater.enable = true;
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

  # XDG Portals
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common.default = "*";
  };

  ##############################################################################
  # Hardware
  ##############################################################################

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  # services.blueman.enable = true; # Optional GUI Bluetooth manager

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

  ##############################################################################
  # Users & Shell
  ##############################################################################

  users.users."joelsgc" = {
    isNormalUser = true;
    description = "JoelSGC";
    extraGroups = [ "networkmanager" "wheel" "globalprotect" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  ##############################################################################
  # System Packages & Nix Settings
  ##############################################################################

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    micro
    git
    sshfs
  ];

  services.flatpak.enable = true;

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

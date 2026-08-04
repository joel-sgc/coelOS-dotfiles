{ inputs, config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./home/kdeconnect.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "coelos"; # Define your hostname.
  networking.firewall.checkReversePath = false;	# Something for ProtonVPN
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

	# Tailscale
  services.tailscale.enable = true;
  networking.firewall.allowedUDPPorts = [ 41641 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Enable Bluetooth support
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true; # Powers up the default Bluetooth Controller on boot
  
  # Optional: Enable Blueman GUI manager (recommended for desktop environments)
  # services.blueman.enable = true;

	services.flatpak.enable = true;

  # Personal Server sshfs
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

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

	# Linking Ghostty to DBus
	services.dbus.packages = [ pkgs.ghostty ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;
  services.libinput.touchpad.naturalScrolling = true;
  services.fprintd.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."joelsgc" = {
    isNormalUser = true;
    description = "JoelSGC";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    micro
    git
    sshfs
  ];

	# Zsh basic config here
  programs.zsh.enable = true;
  users.users.joelsgc.shell = pkgs.zsh;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  nix.settings.experimental-features = [
		"nix-command"
		"flakes"
  ];

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?

  # Disable xterm
  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.excludePackages = [ pkgs.xterm ];

  # Exclude Konsole from the default KDE Plasma installation
  environment.plasma6.excludePackages = with pkgs.kdePackages; [ konsole elisa kwallet kwalletmanager ];

	# Configure plymouth and boot configs
	boot.plymouth = {
     enable = true;
     theme = "coelos"; 
     themePackages = [
       (pkgs.stdenv.mkDerivation {
         pname = "coelos-plymouth-theme";
         version = "1.0";
         # This points to the folder containing your CoelOS theme files
         src = ./coelos-theme;
 
         installPhase = ''
           # Create the correct directory structure in the Nix store
           mkdir -p $out/share/plymouth/themes/coelos
           
           # Copy all pngs, scripts, and plymouth files over
           cp * $out/share/plymouth/themes/coelos/
           
           # Dynamically patch the absolute paths in your .plymouth file
           sed -i "s@^ImageDir=.*@ImageDir=$out/share/plymouth/themes/coelos@" $out/share/plymouth/themes/coelos/coelos.plymouth
           sed -i "s@^ScriptFile=.*@ScriptFile=$out/share/plymouth/themes/coelos/coelos.script@" $out/share/plymouth/themes/coelos/coelos.plymouth
         '';
       })
     ];
   };
 
   # Ensure the kernel parameters are set to show the splash screen
   boot.kernelParams = [ "quiet" "splash" ];
	 boot.initrd.kernelModules = [ "amdgpu" ];
   boot.loader.timeout = 0;
}

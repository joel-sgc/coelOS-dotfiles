{ pkgs, lib, ... }:

let
  # Every entry here is written directly to $XDG_DATA_HOME/applications,
  # not through home-manager's xdg.desktopEntries option -- that module
  # installs via home.packages into the home-manager profile, which is just
  # one entry among many in $XDG_DATA_DIRS and can lose ordering to a
  # package's own shipped .desktop file (confirmed with rofi's own
  # rofi.desktop beating a Hidden stub meant to mask it). $XDG_DATA_HOME is
  # the desktop-entry spec's one true "user override" location -- every
  # consumer checks it first, unconditionally, so an entry placed here
  # always wins.
  #
  # mkDesktopItem below is just pkgs.makeDesktopItem -- the same builder
  # home-manager's own module uses -- so entry generation itself is
  # unchanged; only the install location is.
  mkDesktopItem =
    id: args:
    pkgs.makeDesktopItem (
      {
        name = id;
        type = "Application";
      }
      // args
    );

  # --- Menu declutter -------------------------------------------------
  # A running list of launcher entries that don't belong -- duplicate
  # tools, sub-components better reached through their own umbrella app,
  # or GUIs already configured declaratively elsewhere. Grows as more
  # turn up; add the Desktop ID (the filename without ".desktop", found
  # with e.g. `grep -l '^Name=Cups' /run/current-system/sw/share/applications/*.desktop`)
  # to the list below.
  hiddenDesktopIds = [
    "cups" # printing config GUI; services.printing is already wired declaratively (configuration.nix), don't need the launcher
    "org.kde.qrca" # QR scanner, not used (supersedes the old Keywords-fix entry this file used to carry for it)
    "org.kicad.bitmap2component" # KiCad's own sub-tools -- reachable from the org.kicad.kicad umbrella app, which stays visible
    "org.kicad.eeschema"
    "org.kicad.gerbview"
    "org.kicad.pcbcalculator"
    "org.kicad.pcbnew"
    "qt6ct" # Qt theme is wired declaratively (home/qt-theme.nix), don't need the GUI

    "org.kde.ark" # archive manager GUI, not used
    "btop" # btop++, terminal system monitor -- launched via coel-* menus/keybinds, not a menu entry
    "org.kde.drkonqi.coredump.gui" # crash viewer popup, not something to launch on purpose
    "org.kde.discover" # Plasma's software-center GUI -- packages are managed declaratively here, not imperatively installed
    "org.kde.kdeconnect.nonplasma" # "KDE Connect Indicator" -- the systray applet, not launched directly
    "org.kde.kdeconnect.sms" # KDE Connect's SMS app specifically; org.kde.kdeconnect.app (the main KDE Connect entry) stays visible
    "org.kde.kwalletmanager" # KWallet's own GUI; gnome-keyring is what's actually used here (configuration.nix), not kwallet
    "nixos-manual"
    "org.kde.okular" # Okular, KDE's document viewer, not used
    "org.kde.plasma-systemmonitor" # "System Monitor" -- same reasoning as btop above
    "org.kde.spectacle" # Plasma's screenshot tool -- menu entry only; its own Print-key global shortcut (home/kde-shortcuts.nix) isn't affected, since that invokes the app directly rather than going through this menu entry
  ];

  hiddenEntries = builtins.listToAttrs (
    map (id: {
      name = id;
      value = mkDesktopItem id {
        desktopName = id; # irrelevant once Hidden, just needs to be present
        extraConfig.Hidden = "true";
      };
    }) hiddenDesktopIds
  );

  # --- Field-level overrides for entries that are kept, just wrong -----

  # rpi-imager must run as root on Linux and expects to be launched via
  # pkexec (its own strings/policykit annotations confirm this; it
  # re-drops to the invoking user via runuser/pkexec for xdg-open itself).
  # A polkit agent is already running in both sessions to show the prompt,
  # so no extra polkit rule is needed. Rest of the entry copied verbatim
  # from com.raspberrypi.rpi-imager.desktop, minus zh_CN translations (same
  # convention as the qrca/gimp entries below).
  #
  # Split into a wrapper script rather than an inline `sh -c '...'` Exec=
  # line: the Desktop Entry Spec's Exec= quoting grammar can't express a
  # bare `'` plus an unescaped `$` together, both needed for `"$@"`.
  #
  # Deliberately does NOT `exec` into pkexec -- stays a foreground child
  # and waits. A launcher spawns this script through an intermediate forked
  # process that exits right after the real exec, so replacing this
  # script's own process with pkexec (via `exec`) would leave pkexec a
  # grandchild with an already-dead parent, and it refuses with "Refusing
  # to render service to dead parents" before showing the prompt (known
  # pkexec behavior -- see Fedora/GNOME bug 793445). Keeping this script
  # alive gives pkexec a stable parent for its whole run.
  rpiImagerLaunch = pkgs.writeShellApplication {
    name = "coel-rpi-imager-launch";
    text = ''
      # /run/wrappers/bin/pkexec, not a bare "pkexec": that's the real
      # setuid-root wrapper NixOS installs (security.wrappers); PATH could
      # otherwise resolve to a non-setuid copy that can't escalate.
      #
      # env WAYLAND_DISPLAY=wayland-1: rpi-imager relaunches itself as root
      # via pkexec, then reattaches to the caller's display by scanning
      # /run/user/<uid>/ for anything wayland-looking -- and can pick up
      # home/wallpaper.nix's awww daemon socket instead of the real
      # compositor socket. Forcing the real value (Hyprland's actual socket
      # name here) skips that broken auto-detection.
      /run/wrappers/bin/pkexec env WAYLAND_DISPLAY=wayland-1 ${pkgs.rpi-imager}/bin/rpi-imager "$@"
    '';
  };

  editedEntries = {
    "com.raspberrypi.rpi-imager" = mkDesktopItem "com.raspberrypi.rpi-imager" {
      desktopName = "Raspberry Pi Imager";
      icon = "rpi-imager";
      exec = "${rpiImagerLaunch}/bin/coel-rpi-imager-launch %u";
      startupNotify = false;
      mimeTypes = [
        "x-scheme-handler/rpi-imager"
        "application/vnd.raspberrypi.imager-manifest+json"
      ];
      categories = [ "Utility" ];
    };

    # Cleaner, deduped metadata than the Flatpak-exported originals;
    # written to $XDG_DATA_HOME like everything else here so it actually
    # takes priority over the Flatpak/package originals in $XDG_DATA_DIRS.
    # Every field is copied verbatim from the original except "gcode" in
    # Keywords, dropped below.
    #
    # WEBKIT_DISABLE_DMABUF_RENDERER=1 replaces an earlier
    # LIBGL_ALWAYS_SOFTWARE=1 workaround for a 100%-reproducible segfault on
    # Slice/Save (OrcaSlicer/OrcaSlicer#14453, #15810, #15930). Root cause
    # (confirmed by the upstream fix's author, OrcaSlicer/OrcaSlicer#15873):
    # Flathub's GNOME Platform//50 runtime update (2026-09-19) bumped
    # WebKitGTK -- used by OrcaSlicer's "Home" tab webview -- to 2.54.0,
    # whose DMA-BUF renderer now runs GL on the main thread. That collides
    # with OrcaSlicer's own wx GL canvas when it renders plate thumbnails
    # off-screen (Save/Slice/G-code thumbnails), which calls glDrawElements
    # with no EBO bound in whatever context is current -- real GPU drivers
    # (radeonsi here) segfault on that, llvmpipe happens not to.
    # LIBGL_ALWAYS_SOFTWARE=1 "fixed" it by forcing software rendering for
    # the *entire app*, which is also why the 3D viewport got so much
    # slower. This instead stops WebKitGTK from touching GL at all, so
    # OrcaSlicer's own canvas never loses its context and stays
    # GPU-accelerated. The real fix (PR #15873, merged 2026-09-24) isn't in
    # a tagged release yet -- Flathub's stable branch is still on 2.4.2 as
    # of this writing -- drop this env var entirely once it is.
    "com.orcaslicer.OrcaSlicer" = mkDesktopItem "com.orcaslicer.OrcaSlicer" {
      desktopName = "OrcaSlicer";
      genericName = "3D Printing Software";
      icon = "com.orcaslicer.OrcaSlicer";
      exec = "flatpak run --env=WEBKIT_DISABLE_DMABUF_RENDERER=1 --branch=stable --arch=x86_64 --command=entrypoint --file-forwarding com.orcaslicer.OrcaSlicer @@u %U @@";
      terminal = false;
      mimeTypes = [
        "model/stl"
        "model/3mf"
        "application/vnd.ms-3mfdocument"
        "application/prs.wavefront-obj"
        "application/x-amf"
        "x-scheme-handler/orcaslicer"
        "model/step"
      ];
      categories = [
        "Graphics"
        "3DGraphics"
        "Engineering"
      ];
      startupNotify = false;
      extraConfig = {
        # "gcode" dropped from here, everything else kept
        Keywords = "3D;Printing;Slicer;slice;3D;printer;convert;stl;obj;amf;SLA";
        StartupWMClass = "orca-slicer";
      };
    };

    # Same reasoning as com.orcaslicer.OrcaSlicer above.
    "com.bambulab.BambuStudio" = mkDesktopItem "com.bambulab.BambuStudio" {
      desktopName = "BambuStudio";
      genericName = "3D Printing Software";
      icon = "com.bambulab.BambuStudio";
      exec = "flatpak run --branch=stable --arch=x86_64 --command=entrypoint --file-forwarding com.bambulab.BambuStudio @@u %U @@";
      terminal = false;
      mimeTypes = [
        "model/stl"
        "model/3mf"
        "application/vnd.ms-3mfdocument"
        "application/prs.wavefront-obj"
        "application/x-amf"
        "x-scheme-handler/bambustudio"
        "model/step"
      ];
      categories = [
        "Graphics"
        "3DGraphics"
        "Engineering"
      ];
      startupNotify = false;
      extraConfig = {
        # "gcode" dropped from here, everything else kept
        Keywords = "3D;Printing;Slicer;slice;3D;printer;convert;stl;obj;amf;SLA";
        StartupWMClass = "bambu-studio";
      };
    };

    # Upstream's untranslated Name is "GNU Image Manipulation Program" --
    # the string "gimp" appears nowhere in Name/GenericName/Categories,
    # only in Keywords/Exec, so app-search-by-name found nothing for
    # "gimp" even though it was installed and working. Adds "GIMP" to
    # Name; rest copied verbatim from the real gimp.desktop.
    "gimp" = mkDesktopItem "gimp" {
      desktopName = "GIMP";
      genericName = "Image Editor";
      icon = "gimp";
      exec = "gimp-3.0 %U";
      terminal = false;
      mimeTypes = [
        "image/x-xcf"
        "application/pdf"
        "application/postscript"
        "application/x-navi-animation"
        "image/avif"
        "image/bmp"
        "image/dds"
        "image/g3-fax"
        "image/gif"
        "image/heif"
        "image/hej2k"
        "image/jp2"
        "image/jpeg"
        "image/jxl"
        "image/openraster"
        "image/png"
        "image/qoi"
        "image/svg+xml"
        "image/tiff"
        "image/vnd.microsoft.icon"
        "image/vnd.wap.wbmp"
        "image/webp"
        "image/x-dcm"
        "image/x-dcx"
        "image/x-exr"
        "image/x-fits"
        "image/x-flic"
        "image/x-icns"
        "image/x-ico"
        "image/x-ilbm"
        "image/x-jp2-codestream"
        "image/x-pcx"
        "image/x-pixmap"
        "image/x-portable-anymap"
        "image/x-psd"
        "image/x-psp"
        "image/x-sgi"
        "image/x-sun-raster"
        "image/x-tga"
        "image/x-wmf"
        "image/x-xbitmap"
        "image/x-xwindowdump"
      ];
      categories = [
        "Graphics"
        "2DGraphics"
        "RasterGraphics"
        "GTK"
      ];
      startupNotify = true;
      extraConfig = {
        TryExec = "gimp-3.0";
        Keywords = "GIMP;graphic;design;illustration;painting;";
        StartupWMClass = "gimp";
      };
    };
  };
in
{
  home.file = lib.mapAttrs' (id: item: {
    name = ".local/share/applications/${id}.desktop";
    value.source = "${item}/share/applications/${id}.desktop";
  }) (hiddenEntries // editedEntries);
}

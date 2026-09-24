{ pkgs, lib, ... }:

let
  # Every entry here is written directly to $XDG_DATA_HOME/applications
  # (~/.local/share/applications), not through home-manager's own
  # xdg.desktopEntries option. That module installs entries via
  # home.packages, which lands them in the home-manager *profile*
  # (/etc/profiles/per-user/<user>/share/applications) -- one entry among
  # many in $XDG_DATA_DIRS, competing on ordering with everything else
  # there. Confirmed the hard way: rofi's own wrapped package
  # (rofi-2.0.0, carrying rofi.desktop/rofi-theme-selector.desktop
  # verbatim from upstream) sat earlier in the real $XDG_DATA_DIRS than
  # that profile directory, so rofi found and showed the real entries and
  # never even reached the Hidden stubs meant to mask them.
  #
  # $XDG_DATA_HOME has no such problem: every consumer of the desktop
  # entry spec (confirmed for rofi by reading its actual source; this is
  # the spec's own documented behavior, not a rofi quirk) checks it first,
  # unconditionally, before looking at $XDG_DATA_DIRS at all. That's the
  # one true "user override" location the spec is built around, so an
  # entry placed here always wins regardless of what any package ships or
  # where it happens to sit in the search path.
  #
  # mkDesktopItem below is just pkgs.makeDesktopItem -- the same builder
  # home-manager's own module uses -- so entry generation itself is
  # unchanged; only the install location is.
  mkDesktopItem = id: args: pkgs.makeDesktopItem ({ name = id; type = "Application"; } // args);

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
    "rofi" # rofi's own "launch with default config" entry -- redundant with the coel-* menus/keybinds that actually invoke it
    "rofi-theme-selector"

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

  # rpi-imager needs to run entirely as root on Linux (confirmed in its own
  # binary: it exits with "ERROR: Not running as root." otherwise) and its
  # own strings show it expects to be launched via exactly this pkexec
  # form -- it carries its own org.freedesktop.policykit.exec annotations
  # and separately re-drops to the invoking user via runuser/pkexec for
  # xdg-open. No extra polkit rule is needed: pkexec's built-in generic
  # exec action just requires an admin (wheel) password, which is what
  # `sudo` already gates for this user, and a polkit agent is already
  # running in both sessions (polkit-kde-agent-1, home/hyprland.nix /
  # Plasma's own) to show the graphical prompt. Rest of the entry copied
  # verbatim from the real com.raspberrypi.rpi-imager.desktop, minus the
  # zh_CN translations (same convention as the qrca/gimp entries below).
  # Launches rpi-imager under pkexec. Split into a real wrapper script
  # rather than an inline `sh -c '...'` Exec= line (what this used to be):
  # the Desktop Entry Spec has its own quoting/escaping grammar for Exec=
  # values, separate from real shell syntax, and it rejects a bare `'`
  # outside a quote plus an un-double-backslash-escaped `$` inside one --
  # both unavoidable in an inline `"$@"`. A wrapper script sidesteps that
  # entirely: Exec= just names the script, no embedded quoting at all.
  #
  # Deliberately does NOT `exec` into pkexec -- it runs it as a plain
  # foreground child and waits. A launcher (rofi, gio launch -- confirmed
  # against both) spawns this script through an intermediate forked
  # process that exits the instant the real exec happens, so if this
  # script replaced itself with pkexec (via `exec`), pkexec would end up a
  # *grandchild* of the launcher with a parent that's already gone by the
  # time it runs its own security check -- it refuses with "Refusing to
  # render service to dead parents" before ever showing the polkit prompt.
  # Known, documented pkexec behavior, not specific to rpi-imager -- see
  # e.g. Fedora/GNOME bug 793445 and BunsenLabs' own shipped fix for the
  # identical symptom with other pkexec'd .desktop entries. Keeping this
  # script's own process alive (no `exec`) gives pkexec a direct, stable
  # parent for its whole run, same as running it from an interactive
  # terminal shell (which never hits this).
  rpiImagerLaunch = pkgs.writeShellApplication {
    name = "coel-rpi-imager-launch";
    text = ''
      # /run/wrappers/bin/pkexec, not a bare "pkexec": NixOS installs the
      # real setuid-root wrapper at that fixed path (security.wrappers);
      # a bare "pkexec" depends on PATH resolving there first rather than
      # to some other, non-setuid copy (e.g. plain pkgs.polkit's own,
      # which can't actually escalate and fails immediately with "pkexec
      # must be setuid root").
      #
      # `env WAYLAND_DISPLAY=wayland-1`: rpi-imager relaunches itself as
      # root via pkexec internally, then tries to reattach to the caller's
      # display by scanning /run/user/<uid>/ for anything wayland-looking
      # -- and picks up home/wallpaper.nix's awww daemon socket
      # (wayland-1-awww-daemon.sock) instead of the real compositor socket
      # (wayland-1), since both match. It only auto-detects when the
      # variable isn't already set (confirmed by testing directly, both
      # from a terminal and via this same command), so forcing the real
      # value here is enough to skip that broken detection entirely.
      # "wayland-1" itself isn't discovered dynamically -- it's Hyprland's
      # actual socket name here, confirmed live, but would need updating
      # if this were ever a multi-session machine where that could differ.
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

    # Originally written to fix upstream .desktop entries spuriously
    # matching rofi's `drun` search for "code" (matches against
    # Name/GenericName/Comment/Keywords, not just Name). The real fix for
    # that particular problem is now `drun-match-fields` in home/rofi.nix,
    # which stops rofi from searching Keywords/Comment at all -- these
    # three are kept for their own sake now (cleaner, deduped metadata),
    # written to $XDG_DATA_HOME like everything else in this file so they
    # actually take priority over the Flatpak/package originals instead of
    # just hoping to (that hope is exactly what didn't hold up for these:
    # Flatpak's own exports and the plain nixpkgs originals both sit in
    # $XDG_DATA_DIRS, at positions this file has no control over). Every
    # field below is copied verbatim from the original; only the specific
    # word that accidentally contained "code" is changed.
    "com.orcaslicer.OrcaSlicer" = mkDesktopItem "com.orcaslicer.OrcaSlicer" {
      desktopName = "OrcaSlicer";
      genericName = "3D Printing Software";
      icon = "com.orcaslicer.OrcaSlicer";
      exec = "flatpak run --env=LIBGL_ALWAYS_SOFTWARE=1 --branch=stable --arch=x86_64 --command=entrypoint --file-forwarding com.orcaslicer.OrcaSlicer @@u %U @@";
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

    # Same fix, same reasoning, as com.orcaslicer.OrcaSlicer above -- copied
    # verbatim from ~/.local/share/flatpak/exports/share/applications/
    # com.bambulab.BambuStudio.desktop, "gcode" dropped from Keywords.
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

    # Different failure mode than the other three: this isn't about a
    # keyword false-matching, it's the opposite -- rofi's
    # "drun-match-fields" = "name,generic,categories" (home/rofi.nix)
    # stopped matching against Keywords/Exec entirely, and upstream's own
    # (untranslated) Name is "GNU Image Manipulation Program" -- the
    # string "gimp" appears nowhere in Name, GenericName ("Image Editor"),
    # or Categories, only in Keywords/Exec, which are exactly the fields
    # that change stopped searching. So typing "gimp" in rofi drun found
    # nothing, even though the app was installed and working fine. Fix is
    # the same shape as the others -- override just the field that
    # doesn't survive the stricter match -- but here that means *adding*
    # "GIMP" to Name rather than removing a word from it. Rest copied
    # verbatim from the real gimp.desktop.
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

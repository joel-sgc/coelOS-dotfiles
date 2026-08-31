{ ... }:

{
  # Originally written to fix upstream .desktop entries spuriously matching
  # rofi's `drun` search for "code" (matches against Name/GenericName/
  # Comment/Keywords, not just Name), on the assumption that home-manager's
  # generated .desktop file always shadows the original in XDG_DATA_DIRS
  # resolution order. That's not reliably true -- Flatpak's own exported
  # entries (~/.local/share/flatpak/exports/share/applications/) sit
  # *earlier* in XDG_DATA_DIRS than the home-manager profile, so for
  # Flatpak apps specifically, these don't actually win. The real fix for
  # the rofi search problem is now `drun-match-fields` in home/rofi.nix,
  # which stops rofi from searching Keywords/Comment at all. These entries
  # are kept anyway for their own sake -- cleaner, deduped metadata for
  # any other consumer of these files -- not because they still shadow
  # anything for rofi's purposes. Every field below is copied verbatim
  # from the original; only the specific word that accidentally contained
  # "code" is changed.
  xdg.desktopEntries = {
    # Now overrides the Flatpak's own generated entry (~/.local/share/
    # flatpak/exports/share/applications/com.orcaslicer.OrcaSlicer.desktop)
    # instead of the native package's -- native orca-slicer install was
    # dropped in favor of the Flatpak (home/flatpak.nix). Exec/Icon copied
    # verbatim from that generated entry; "gcode" is still dropped from
    # Keywords for the same reason as before (it contains "code" as a
    # substring, which spuriously matched rofi drun's "code" search).
    #
    # The attribute name has to be the Flatpak's real Desktop ID
    # (com.orcaslicer.OrcaSlicer), not a friendly "OrcaSlicer" -- the
    # shadowing this file relies on only works when the generated filename
    # matches exactly. A friendly name here just produces a *second*,
    # unrelated .desktop file that coexists instead of overriding anything.
    "com.orcaslicer.OrcaSlicer" = {
      name = "OrcaSlicer";
      genericName = "3D Printing Software";
      icon = "com.orcaslicer.OrcaSlicer";
      exec = "flatpak run --branch=stable --arch=x86_64 --command=entrypoint --file-forwarding com.orcaslicer.OrcaSlicer @@u %U @@";
      terminal = false;
      mimeType = [
        "model/stl"
        "model/3mf"
        "application/vnd.ms-3mfdocument"
        "application/prs.wavefront-obj"
        "application/x-amf"
        "x-scheme-handler/orcaslicer"
        "model/step"
      ];
      categories = [ "Graphics" "3DGraphics" "Engineering" ];
      startupNotify = false;
      settings = {
        # "gcode" dropped from here, everything else kept
        Keywords = "3D;Printing;Slicer;slice;3D;printer;convert;stl;obj;amf;SLA";
        StartupWMClass = "orca-slicer";
      };
    };

    # Same fix, same reasoning, as com.orcaslicer.OrcaSlicer above -- copied
    # verbatim from ~/.local/share/flatpak/exports/share/applications/
    # com.bambulab.BambuStudio.desktop, "gcode" dropped from Keywords.
    "com.bambulab.BambuStudio" = {
      name = "BambuStudio";
      genericName = "3D Printing Software";
      icon = "com.bambulab.BambuStudio";
      exec = "flatpak run --branch=stable --arch=x86_64 --command=entrypoint --file-forwarding com.bambulab.BambuStudio @@u %U @@";
      terminal = false;
      mimeType = [
        "model/stl"
        "model/3mf"
        "application/vnd.ms-3mfdocument"
        "application/prs.wavefront-obj"
        "application/x-amf"
        "x-scheme-handler/bambustudio"
        "model/step"
      ];
      categories = [ "Graphics" "3DGraphics" "Engineering" ];
      startupNotify = false;
      settings = {
        # "gcode" dropped from here, everything else kept
        Keywords = "3D;Printing;Slicer;slice;3D;printer;convert;stl;obj;amf;SLA";
        StartupWMClass = "bambu-studio";
      };
    };

    # Original (KDE's org.kde.qrca.desktop) has Comment="Scan and create
    # QR-Codes" -- "Codes" contains "code" as a substring. Only the base
    # (untranslated) Name/GenericName/Comment are reproduced here, not
    # every one of upstream's ~40 per-locale translations.
    # Different failure mode than the other three entries here: this isn't
    # about a keyword false-matching, it's the opposite -- rofi's
    # "drun-match-fields" = "name,generic,categories" (above) stopped
    # matching against Keywords/Exec entirely, and upstream's own
    # (untranslated) Name is "GNU Image Manipulation Program" -- the
    # string "gimp" appears nowhere in Name, GenericName ("Image Editor"),
    # or Categories, only in Keywords/Exec, which are exactly the fields
    # that change just stopped searching. So typing "gimp" in rofi drun
    # found nothing, even though the app was installed and working fine.
    # Fix is the same shape as the others -- override just the field that
    # doesn't survive the stricter match -- but here that means *adding*
    # "GIMP" to Name rather than removing a word from it. Rest copied
    # verbatim from the real gimp.desktop.
    "gimp" = {
      name = "GIMP";
      genericName = "Image Editor";
      icon = "gimp";
      exec = "gimp-3.0 %U";
      terminal = false;
      mimeType = [
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
      categories = [ "Graphics" "2DGraphics" "RasterGraphics" "GTK" ];
      startupNotify = true;
      settings = {
        TryExec = "gimp-3.0";
        Keywords = "GIMP;graphic;design;illustration;painting;";
        StartupWMClass = "gimp";
      };
    };

    "org.kde.qrca" = {
      name = "Qrca";
      # Original GenericName was "Barcode Scanner" -- also contains "code"
      # (inside "Barcode"), same problem as Comment below.
      genericName = "QR Scanner";
      comment = "Scan and create QR pictures";
      icon = "org.kde.qrca";
      exec = "qrca";
      terminal = false;
      categories = [ "Qt" "KDE" "Utility" ];
      settings = {
        Version = "1.0";
        SingleMainWindow = "true";
      };
    };
  };
}

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

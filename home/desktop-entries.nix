{ pkgs, ... }:

{
  # Overrides for upstream .desktop entries that spuriously match rofi's
  # `drun` search for "code" (which matches against Name/GenericName/
  # Comment/Keywords, not just Name) -- home-manager's xdg.desktopEntries
  # generates a same-named .desktop file with hiPrio, which shadows the
  # nix-store original in XDG_DATA_DIRS resolution order. Every other
  # field below is copied verbatim from the original; only the specific
  # word that accidentally contained "code" is changed.
  xdg.desktopEntries = {
    # Original (orca-slicer's own share/applications/OrcaSlicer.desktop)
    # has "gcode" in Keywords -- accurate (it's a G-code-producing slicer),
    # but "gcode" contains "code" as a substring, so it matched.
    OrcaSlicer = {
      name = "OrcaSlicer";
      genericName = "3D Printing Software";
      icon = "OrcaSlicer";
      exec = "${pkgs.orca-slicer}/bin/orca-slicer %U";
      terminal = false;
      mimeType = [
        "model/stl"
        "model/3mf"
        "application/vnd.ms-3mfdocument"
        "application/prs.wavefront-obj"
        "application/x-amf"
        "x-scheme-handler/orcaslicer"
      ];
      categories = [ "Graphics" "3DGraphics" "Engineering" ];
      startupNotify = false;
      settings = {
        # "gcode" dropped from here, everything else kept
        Keywords = "3D;Printing;Slicer;slice;3D;printer;convert;stl;obj;amf;SLA";
        StartupWMClass = "orca-slicer";
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

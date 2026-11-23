{ lib, ... }:

let
  zen = "zen.desktop";

  # Formats a browser can actually render. Zen's own .desktop file only
  # declares html/http(s), but GIO and xdg-mime both honor a default listed
  # in mimeapps.list even when the app doesn't declare the type, so no
  # desktop-entry override is needed to make these stick.
  images = [
    "image/png"
    "image/jpeg"
    "image/gif"
    "image/webp"
    "image/avif"
    "image/apng"
    "image/svg+xml"
    "image/bmp"
    "image/vnd.microsoft.icon"
    "image/x-icon"
    "image/jxl"
    "image/tiff"
  ];

  # mkv and mov only play if the codecs inside are ones Firefox can decode.
  videos = [
    "video/mp4"
    "video/webm"
    "video/ogg"
    "video/x-matroska"
    "video/quicktime"
    "video/mpeg"
    "video/x-msvideo"
    "video/3gpp"
  ];

  # Plain-text-ish types open in micro in a Ghostty window (micro.desktop, see
  # home/micro.nix). The list is shared with that file.
  textTypes = import ./text-mime.nix;

  # Firefox's built-in pdf.js viewer.
  documents = [
    "application/pdf"
  ];
in
{
  xdg.mimeApps = {
    enable = true;

    defaultApplications = lib.genAttrs (images ++ videos ++ documents) (_: [ zen ])
    // lib.genAttrs textTypes (_: [ "micro.desktop" ])
    // {
      # Ported from the previous unmanaged ~/.config/mimeapps.list (Zen
      # had registered itself as the browser there). Must be carried over:
      # this file replaces that one outright.
      "text/html" = [ zen ];
      "application/xhtml+xml" = [ zen ];
      "application/x-extension-htm" = [ zen ];
      "application/x-extension-html" = [ zen ];
      "application/x-extension-shtml" = [ zen ];
      "application/x-extension-xht" = [ zen ];
      "application/x-extension-xhtml" = [ zen ];
      # Via home/chromium.nix's router: cad.onshape.com links open the
      # Onshape app, everything else falls through to Zen.
      "x-scheme-handler/http" = [ "coel-url-router.desktop" ];
      "x-scheme-handler/https" = [ "coel-url-router.desktop" ];
      "x-scheme-handler/chrome" = [ zen ];

      # Bambu Studio's "Open in Bambu Studio" links (Printables,
      # MakerWorld) open in OrcaSlicer instead. Orca's binary carries its
      # own bambustudio://open handling. Both apps are the Flatpak builds
      # (home/flatpak.nix), so this is the Flatpak's desktop ID.
      "x-scheme-handler/bambustudio" = [ "com.orcaslicer.OrcaSlicer.desktop" ];
    };
  };

  # The existing ~/.config/mimeapps.list is a plain file Zen/KDE apps wrote, not
  # something home-manager owns, and activation refuses to clobber those.
  # Everything in it that mattered is reproduced above. force also covers
  # the future: KDE's "Open With" replaces this symlink with a regular file
  # when it saves a choice, and this puts the declared version back on the
  # next activation instead of failing.
  xdg.configFile."mimeapps.list".force = true;
}

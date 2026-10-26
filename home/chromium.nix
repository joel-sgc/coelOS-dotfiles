{ pkgs, lib, ... }:

let
  # Chromium "install as app" sites, declared here instead of installed by
  # hand. Add a site = add a line (and drop a PNG in assets/webapp-icons/).
  # Written straight to $XDG_DATA_HOME/applications via home.file rather than
  # xdg.desktopEntries, for the same ordering reason as home/desktop-entries.nix.
  # --app=URL (not --app-id) so nothing depends on PWA state in the profile.
  webapps = {
    slack = {
      name = "Slack";
      url = "https://app.slack.com/client/T0A6685TESC/";
    };
    whatsapp = {
      name = "WhatsApp Web";
      url = "https://web.whatsapp.com/";
    };
    groupme = {
      name = "GroupMe";
      url = "https://web.groupme.com/";
    };
    onshape = {
      name = "Onshape";
      url = "https://cad.onshape.com/";
    };
  };

  mkWebapp =
    id: app:
    pkgs.makeDesktopItem {
      name = "webapp-${id}";
      desktopName = app.name;
      exec = "chromium --class=webapp-${id} --app=${app.url}";
      icon = ../assets/webapp-icons + "/${id}.png";
      categories = [ "Network" ];
      startupNotify = true;
      extraConfig.StartupWMClass = "webapp-${id}";
    };
in
{
  home.file = lib.mapAttrs' (id: app: {
    name = ".local/share/applications/webapp-${id}.desktop";
    value.source = "${mkWebapp id app}/share/applications/webapp-${id}.desktop";
  }) webapps;

  programs.chromium = {
    enable = true;
    package = pkgs.chromium;

    # No commandLineArgs for Wayland: nixpkgs' chromium wrapper already
    # switches to the native Wayland backend when NIXOS_OZONE_WL is set,
    # which home.nix sets globally.

    # Same pair as home/zen-browser.nix. Find IDs in the Chrome Web Store URL.
    # These are dropped in ~/.config/chromium/External Extensions/ and get
    # offered for install on the next launch (Chromium asks you to enable
    # them once from the toolbar menu).
    extensions = [
      # uBlock Origin *Lite*, not classic uBlock Origin: Chromium dropped
      # Manifest V2 entirely (we're on 150), and classic uBO is MV2 only,
      # so it would silently fail to load.
      { id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; } # uBlock Origin Lite
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
    ];
  };
}

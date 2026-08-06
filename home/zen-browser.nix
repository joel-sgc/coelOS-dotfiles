{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  extension = shortId: guid: {
    name = guid;
    value = {
      install_url = "https://addons.mozilla.org/en-US/firefox/downloads/latest/${shortId}/latest.xpi";
      installation_mode = "normal_installed";
      default_area = "navbar"; # Pins the toolbar button by default
    };
  };

  prefs = {
    # Check these out at about:config
    "extensions.autoDisableScopes" = 0;
    "extensions.pocket.enabled" = false;
		"browser.ctrlTab.sortByRecentlyUsed" = true;
		"zen.view.use-single-toolbar" = false;
		"zen.view.sidebar-expanded" = false;
		"zen.window-sync.enabled" = false;
		"signon.rememberSignons" = false;
		"extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
		"layout.css.prefers-color-scheme.content-override" = 0;
		"ui.systemUsesDarkTheme" = 1;
		"browser.startup.homepage_override.mstone" = "ignore";
		"startup.homepage_welcome_url.additional" = "";
		"browser.startup.firstrunSkipsHomepage" = false;
		"browser.aboutwelcome.enabled" = false;
  };

  extensions = [
    # To add additional extensions, find it on addons.mozilla.org, find
    # the short ID in the url (like https://addons.mozilla.org/en-US/firefox/addon/!SHORT_ID!/)
    # Then go to https://addons.mozilla.org/api/v5/addons/addon/!SHORT_ID!/ to get the guid
    (extension "ublock-origin" "uBlock0@raymondhill.net")
    (extension "bitwarden-password-manager" "{446900e4-71c2-419f-a6a7-df9c091e268b}")
  ];

in
{
  home.packages = [
    (pkgs.wrapFirefox
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.zen-browser-unwrapped
      {
        extraPrefs = lib.concatLines (
          lib.mapAttrsToList (
            name: value: ''lockPref(${lib.strings.toJSON name}, ${lib.strings.toJSON value});''
          ) prefs
        );

        extraPolicies = {
          DisableTelemetry = true;
          ExtensionSettings = builtins.listToAttrs extensions;
          OverrideFirstRunPage = "";
          DisableFirefoxStudies = true;
          DisablePocket = true;
          DisableAccounts = true;
          DisableFormHistory = true;
          DisableBookmarksToolbar = "never";
          Preferences = {
          	"browser.tabs.warnOnClose" = false;
          	"privacy.trackingprotection.enabled" = true;
          	"privacy.donottrackheader.enabled" = true;
          };

          SearchEngines = {
            Default = "ddg";
            Add = [
              {
                Name = "nixpkgs packages";
                URLTemplate = "https://search.nixos.org/packages?query={searchTerms}";
                IconURL = "https://wiki.nixos.org/favicon.ico";
                Alias = "@np";
              }
              {
                Name = "NixOS options";
                URLTemplate = "https://search.nixos.org/options?query={searchTerms}";
                IconURL = "https://wiki.nixos.org/favicon.ico";
                Alias = "@no";
              }
              {
                Name = "NixOS Wiki";
                URLTemplate = "https://wiki.nixos.org/w/index.php?search={searchTerms}";
                IconURL = "https://wiki.nixos.org/favicon.ico";
                Alias = "@nw";
              }
              {
                Name = "noogle";
                URLTemplate = "https://noogle.dev/q?term={searchTerms}";
                IconURL = "https://noogle.dev/favicon.ico";
                Alias = "@ng";
              }
              {
              	Name = "Youtube";
              	URLTemplate = "https://www.youtube.com/results?search_query={searchTerms}";
              	IconURL = "https://www.youtube.com/favicon.ico";
              	Alias = "y";
              }
            ];
          };
        };
      }
    )
  ];
}

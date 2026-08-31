{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config.lib.formats.rasi) mkLiteral;

  theme = import ./theme/onedark.nix;

  # --- Menu scripts -----------------------------------------------------
  # Ported from the old Arch/Omarchy dotfiles' configs/rofi/*.sh. Every menu
  # entry from the originals is present here — anything without a real Nix
  # equivalent yet shows a TODO notification (via coel-todo) instead of being
  # silently dropped. Styling is still deferred on purpose (unstyled rofi/
  # waybar, per the "get it working first" priority) — that hasn't changed,
  # only completeness has.
  #
  # Other adaptations:
  #   - alacritty -> ghostty (our terminal)
  #   - absolute ~/.coelOS-dotfiles paths -> bare command names (these are
  #     all on PATH via home.packages, same as each other)
  #   - fixed: `-p` was missing its prompt-text argument in every menu
  #     script in the original (e.g. `-p -lines 10 ... -i "Power"` — the
  #     trailing quoted string was never actually reaching -p); now `-p
  #     "Power"` etc. directly, `-i` kept as rofi's real case-insensitive flag
  #   - fixed: power-profiles.sh captured `$?` *after* the `powerprofilesctl
  #     set` call instead of right after the rofi prompt, so the
  #     cancel-reopens-menu behavior was checking the wrong command's exit
  #     code. Moved it back to directly after the prompt.
  #
  # The menu scripts below (power/actions/settings/power-profiles/
  # fingerprint/config) keep the original's un-guarded `choice=$(rofi ...)`
  # followed by a bare `exit_code=$?` check to decide whether rofi was
  # cancelled. That relies on the script *not* aborting when rofi exits
  # non-zero, so these are plain writeShellScriptBin (no `set -e`) rather
  # than writeShellApplication, on purpose.

  todo = pkgs.writeShellApplication {
    name = "coel-todo";
    runtimeInputs = [ pkgs.libnotify ];
    text = ''
      notify-send -a "CoelOS" -u normal "TODO" "''${1:-Not wired up yet.}"
    '';
  };

  # `--class=com.joelsgc.floating`/`com.joelsgc.info` below tag one-off
  # utility ghostty windows so home/hyprland.nix's windowrules float them
  # instead of tiling -- ported from the old dotfiles' equivalent
  # `alacritty --class com.joelsgc.floating -e ...` convention.

  # Place these 2 in between "Settings" and "Update" when ready
  # 󱧘  Install\n\
  # 󱧙  Uninstall\n\
  mainMenu = pkgs.writeShellApplication {
    name = "coel-main-menu";
    runtimeInputs = [ pkgs.rofi ];
    text = ''
            choice=$(printf \
            "󰀻  Programs\n\
      󱓞  Actions\n\
        Settings\n\
        Rebuild\n\
        Update\n\
        About\n\
      󰤆  System\n" | rofi -dmenu -i -p "Main Menu" -no-fixed-num-lines)

            case "$choice" in
            	*Programs*) rofi -show drun -theme-str 'listview { lines: 10; }' ;;
            	*Actions*) exec coel-actions-menu ;;
            	*Settings*) exec coel-settings-menu ;;
            	*Install*) exec ghostty --class=com.joelsgc.floating -e coel-package-search ;;
            	*Uninstall*) exec coel-todo "Nix has no imperative package uninstaller menu — remove the package from home.nix or configuration.nix and rebuild instead." ;;
            	*Rebuild*) exec ghostty --class=com.joelsgc.floating -e coel-rebuild ;;
            	*Update*) exec ghostty --class=com.joelsgc.floating -e coel-update ;;
            	*About*) exec ghostty --class=com.joelsgc.info -e bash -c "fastfetch; read -n1 -r" ;;
            	*System*) exec coel-power-menu ;;
            esac
    '';
  };

  # `Update` in the old menu ran a pacman/yay/flatpak wrapper script. Split
  # into two here since Nix distinguishes "rebuild from the current
  # flake.lock" from "pull newer flake inputs first, then rebuild": Rebuild
  # is the direct equivalent (same command as ~/reload-nix.sh), Update is
  # the same thing plus `--upgrade` to update flake inputs (nixpkgs, etc.)
  # before building.
  rebuild = pkgs.writeShellApplication {
    name = "coel-rebuild";
    text = ''
      echo "Rebuilding CoelOS: sudo nixos-rebuild switch --flake ~/.nixos#coelos"
      echo
      sudo nixos-rebuild switch --flake "$HOME/.nixos#coelos"
      echo
      read -n 1 -s -r -p "Done. Press any key to close..."
      echo
    '';
  };

  update = pkgs.writeShellApplication {
    name = "coel-update";
    text = ''
      echo "Updating CoelOS: sudo nixos-rebuild switch --flake ~/.nixos#coelos --upgrade"
      echo
      sudo nixos-rebuild switch --flake "$HOME/.nixos#coelos" --upgrade
      echo
      read -n 1 -s -r -p "Done. Press any key to close..."
      echo
    '';
  };

  # Nix has no imperative installer, so this is a *search*, not an install:
  # look up a package and copy the resolved `pkgs.<attr>` path(s) to the
  # clipboard so they can be pasted straight into home.nix's/
  # configuration.nix's package lists.
  #
  # `nix search nixpkgs` (local eval of every one of ~108k package
  # attributes) was tried first and genuinely wasn't good enough: no
  # up-front narrowing meant "tests.*" internal test derivations and other
  # junk cluttered results, and naive substring matching against the whole
  # line meant queries like "ncdu" could match unrelated packages whose
  # *description* happened to mention it. Rebuilt instead on `nix-search`
  # (nixpkgs' `nix-search-cli`), which queries the same relevance-ranked
  # Elasticsearch index behind search.nixos.org -- same backend the
  # official website uses, so junk/false-positive filtering is already
  # solved upstream instead of hand-rolled here.
  #
  # fzf's `--disabled` + `change:reload` is the standard pattern for a live
  # external-search UI: fzf stops doing its own local filtering entirely
  # and just displays whatever coel-package-search-query returns for the
  # current query text ({q}), re-run on every keystroke -- true
  # search-as-you-type against the real API, no local package list at all.
  packageSearchQuery = pkgs.writeShellApplication {
    name = "coel-package-search-query";
    runtimeInputs = [
      pkgs.nix-search-cli
      pkgs.jq
      pkgs.gawk
    ];
    text = ''
      query="''${1:-}"
      if [ -z "$query" ]; then
        exit 0
      fi

      # Channel matches this flake's nixpkgs input (flake.nix: nixos-26.05)
      # as closely as search.nixos.org's indexed channels allow -- attribute
      # names/paths are stable enough across a release line that an exact
      # revision match isn't necessary for this to be useful.
      nix-search --channel=26.05 --search "$query" --json --max-results 60 2>/dev/null | jq -r '
        [.package_attr_name, (.package_pversion // "?"), (.package_description // "no description")]
        | @tsv
      ' | awk -F'\t' '{ printf "%-40s  %-16s  %s\n", $1, $2, $3 }'
    '';
  };

  # Modeled on the old Arch/Omarchy dotfiles' bin/pacman-install.sh and
  # bin/yay-install.sh: an fzf TUI with a live preview pane, multi-select
  # (tab), and pointer/marker colored to match the theme -- run inside a
  # floating ghostty (see home/hyprland.nix's `com.joelsgc.floating`
  # windowrule) rather than a rofi popup. `pointer:green,marker:green` below
  # is fzf's *named* ANSI color, not a literal hex -- it resolves through
  # whatever ghostty theme is active (ANSI 2), so no hardcoded color needs
  # to track theme changes. Proven when this went from Everforest to
  # Dracula with zero changes needed here.
  packageSearch = pkgs.writeShellApplication {
    name = "coel-package-search";
    runtimeInputs = [
      pkgs.fzf
      pkgs.gawk
      pkgs.wl-clipboard
      showDone
      packageSearchQuery
    ];
    text = builtins.readFile ./rofi/scripts/coel-package-search.sh;
  };

  powerMenu = pkgs.writeShellScriptBin "coel-power-menu" (builtins.readFile ./rofi/scripts/power-menu.sh);

  actionsMenu = pkgs.writeShellScriptBin "coel-actions-menu" (builtins.readFile ./rofi/scripts/actions-menu.sh);

  settingsMenu = pkgs.writeShellScriptBin "coel-settings-menu" (builtins.readFile ./rofi/scripts/settings-menu.sh);

  # Ported from config.sh. Monitors/Keybindings/Input/Autostart/Window Rules
  # all used to be separate files; ours are unified into home/hyprland.nix
  # (hyprlock/hypridle settings live in home/hypridle.nix), so several
  # entries below point at the same file — that's a real difference from the
  # old per-concern file split, not a mistake.
  configMenu = pkgs.writeShellScriptBin "coel-config-menu" (builtins.readFile ./rofi/scripts/config-menu.sh);

  powerProfilesMenu = pkgs.writeShellScriptBin "coel-power-profiles-menu" ''
    #!/usr/bin/env bash
    profiles=$(powerprofilesctl list | awk '/:$/ {gsub("\\*",""); gsub(":",""); print $1}')

    chosen=$(echo "$profiles" | rofi -dmenu -i -p "Power Profiles" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    if [ -n "$chosen" ]; then
        powerprofilesctl set "$chosen"
    fi

    if [ "$exit_code" -ne 0 ]; then
        exec coel-settings-menu
    fi
  '';

  emojiPicker = pkgs.writeShellApplication {
    name = "coel-emoji-picker";
    runtimeInputs = [ pkgs.rofi ];
    text = ''
      rofi -modi emoji -show emoji -theme-str "window {width: 768px;}" -lines 10 -no-fixed-num-lines
    '';
  };

  # --- Screenshot / screen recording -------------------------------------
  # Ported from bin/screenshot.sh and bin/screenrecord.sh — these had no
  # Arch/Omarchy-package-manager dependencies at all, just Wayland tooling,
  # so they came over unmodified apart from PATH resolution.
  screenshot = pkgs.writeShellApplication {
    name = "coel-screenshot";
    runtimeInputs = with pkgs; [
      grim
      slurp
      wayfreeze
      satty
      jq
      hyprland
      wl-clipboard
      libnotify
    ];
    text = builtins.readFile ./rofi/scripts/coel-screenshot.sh;
  };

  screenrecord = pkgs.writeShellApplication {
    name = "coel-screenrecord";
    runtimeInputs = with pkgs; [
      gpu-screen-recorder
      v4l-utils
      ffmpeg
      hyprland
      jq
      libnotify
      waybar
      procps
    ];
    text = builtins.readFile ./rofi/scripts/coel-screenrecord.sh;
  };

  # --- Fingerprint helpers ------------------------------------------------
  showDone = pkgs.writeShellApplication {
    name = "coel-show-done";
    runtimeInputs = [ pkgs.gum ];
    text = ''
      TITLE="''${1:-Done! Press any key to close...}"
      echo
      gum spin --spinner "globe" --title "$TITLE" -- bash -c 'read -n 1 -s'
    '';
  };

  fingerprintEnroll = pkgs.writeShellApplication {
    name = "coel-fingerprint-enroll";
    runtimeInputs = [
      pkgs.fprintd
      showDone
    ];
    text = ''
      sudo pkill fprintd || true
      sudo fprintd-enroll "$USER"
      exec coel-show-done
    '';
  };

  fingerprintDelete = pkgs.writeShellApplication {
    name = "coel-fingerprint-delete";
    runtimeInputs = [ showDone ];
    text = ''
      sudo -v
      sleep 0.2
      sudo fprintd-delete "$USER"
      exec coel-show-done
    '';
  };

  # Ported from uninstall.sh's Fingerprint entry (delete) + settings.sh's
  # Fingerprint entry (enroll) — the original split enroll/delete across two
  # different top-level menus (Settings vs. Uninstall); since Uninstall is
  # now a TODO stub (see mainMenu), both live together here instead so
  # fingerprintDelete still has somewhere to be reached from.
  fingerprintMenu = pkgs.writeShellScriptBin "coel-fingerprint-menu" ''
    #!/usr/bin/env bash
    choice=$(printf \
    "   Enroll\n\
       Delete\n" | rofi -dmenu -i -p "Fingerprint" -lines 10 -no-fixed-num-lines)

    exit_code=$?

    case "$choice" in
    	*Enroll*) exec ghostty --class=com.joelsgc.floating -e coel-fingerprint-enroll ;;
    	*Delete*) exec ghostty --class=com.joelsgc.floating -e coel-fingerprint-delete ;;
    esac

    if [ "$exit_code" -ne 0 ]; then
        exec coel-settings-menu
    fi
  '';
in
{
  # rofi-emoji needs to be baked into the rofi package itself (rofi loads
  # modi plugins from its own plugin path), so this replaces the plain
  # pkgs.rofi package that used to live in home.nix's home.packages.
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    plugins = [ pkgs.rofi-emoji ];

    # Ported structurally verbatim from the old Arch/Omarchy dotfiles'
    # theme/rofi.rasi (window/listview/element layout, spacing, the
    # icon-current-entry preview pane, etc.) -- only the color source
    # changed. The original hardcoded `* { urgent: #ff99da; accent:
    # #7acdcd; text: #d4d4d4; base: #262626; }` at the top of the same
    # file; those four vars are now sourced from the static One Dark
    # palette (home/theme/onedark.nix) instead, so @urgent/@accent/
    # @text/@base below resolve the same way they did against the inline
    # block originally.
    #
    # Not ported: an `@media (enabled: env(PREVIEW, false))` block that
    # swapped in a split icon-preview layout. That's Omarchy's own
    # rofi-theme-selector preview tooling reaching into an env var we have
    # no equivalent producer for, and `@media`/`env()` conditionals aren't
    # common enough rofi syntax to risk shipping unverified -- dropped
    # rather than guessed at.
    theme = {
      "*" = {
        # Single font, matching `font` below -- the original dotfiles'
        # theme/rofi.rasi declared `"JetBrainsMonoNL Nerd Font 24, FiraCode
        # Nerd Font Mono 16"` here, which is not a valid Pango font
        # description (only one trailing size is recognized; a second size
        # embedded mid-string gets swallowed into the first family name,
        # e.g. "JetBrainsMonoNL Nerd Font 24" as a literal, nonexistent
        # family). That's almost certainly why icons rendered inconsistently
        # -- font resolution for the first fallback was silently broken.
        # Standardized on FiraCode Nerd Font Mono (matching home/ghostty.nix)
        # instead of JetBrainsMono -- one Nerd Font across the whole desktop.
        font = "FiraCode Nerd Font Mono 20";
        urgent = mkLiteral theme.yellow;
        accent = mkLiteral theme.blue;
        text = mkLiteral theme.fg;
        base = mkLiteral theme.bg;
      };

      window = {
        width = mkLiteral "512px";
        "border-radius" = mkLiteral "8px";
        border = mkLiteral "2px";
        "border-color" = mkLiteral "@accent";
        padding = mkLiteral "48px";
        "background-color" = mkLiteral "@base";
      };

      wrap = {
        expand = false;
        children = [ (mkLiteral "inputbar") ];
      };

      "mainbox, listview, element, element-text, entry, wrap, listview-split, icon-current-entry" = {
        "background-color" = mkLiteral "transparent";
      };

      listview = {
        spacing = mkLiteral "16px";
        padding = mkLiteral "16px 0 0 0";
      };

      "listview-split" = {
        orientation = mkLiteral "horizontal";
        spacing = mkLiteral "24px";
        children = map mkLiteral [
          "listview"
          "icon-current-entry"
        ];
      };

      element = {
        padding = mkLiteral "8px";
      };

      "element-text" = {
        "text-color" = mkLiteral "@accent";
      };

      "element-text selected" = {
        "text-color" = mkLiteral "@urgent";
      };

      "element-icon" = {
        size = mkLiteral "0px";
      };

      "icon-current-entry" = {
        expand = false;
        size = mkLiteral "35%";
      };

      inputbar = {
        padding = mkLiteral "12px";
        children = [ (mkLiteral "entry") ];
        "background-color" = mkLiteral "@base";
      };

      entry = {
        placeholder = "Go...";
        "placeholder-color" = mkLiteral "@text";
        "text-color" = mkLiteral "@text";
      };
    };

    # Ported from the old config.rasi's `configuration { ... }` block,
    # except the size: the original left it unsized here while theme/rofi.rasi
    # set a (broken, see above) JetBrainsMono-based font -- two different
    # fonts for the same UI. Normalized to the single font above so every
    # rofi surface resolves identically.
    font = "FiraCode Nerd Font Mono 20";
    extraConfig = {
      "disable-history" = true;
      "disable-sort" = false;
      matching = "normal";
      "scroll-method" = 1;

      # Default drun match fields are name,generic,exec,categories,keywords.
      # Keywords is a free-for-all bag upstream apps stuff arbitrary terms
      # into (e.g. OrcaSlicer/BambuStudio both list "gcode", which matches
      # any search for "code") and exec is just the raw launch command --
      # neither is useful search text, and per-app .desktop overrides to
      # scrub specific offending words (see home/desktop-entries.nix) don't
      # reliably win anyway: Flatpak's own exported entries sit earlier in
      # XDG_DATA_DIRS than the home-manager profile, so they're not even
      # being shadowed right now. This fixes the whole class of "keyword
      # happens to contain a common substring" false positives at once,
      # for every app, present and future, without depending on winning
      # that ordering race at all.
      "drun-match-fields" = "name,generic,categories";
    };
  };

  home.packages = [
    todo
    mainMenu
    rebuild
    update
    packageSearchQuery
    packageSearch
    powerMenu
    actionsMenu
    settingsMenu
    configMenu
    powerProfilesMenu
    emojiPicker
    screenshot
    screenrecord
    showDone
    fingerprintEnroll
    fingerprintDelete
    fingerprintMenu
    pkgs.hyprpicker
    pkgs.pulsemixer
  ];
}

{ ... }:

# Per-game Steam workarounds, declared instead of clicked into Steam's UI.
# The steam-config-nix module (flake input) writes them into Steam's own
# config the next time Steam is closed -- Steam rewrites its config files
# from memory on exit, so anything written while it's running would be
# discarded. Steam itself is enabled system-wide in configuration.nix
# (Gaming section); this file is only the per-game layer.
#
# To add a game: find its App ID (the number in its store page URL, e.g.
# store.steampowered.com/app/1091500/ -> "1091500") and add an entry under
# `apps`. Full docs and every option:
#   https://different-name.github.io/steam-config-nix/docs/
#
# Things a game entry can carry (all optional, combine freely):
#   compatTool     a Proton build: pkgs.proton-ge-bin, or a name Steam
#                  already has, like "proton_experimental"
#   dllOverrides   Wine DLL overrides, e.g. the winhttp one BepInEx needs
#   env / args     environment variables / extra game arguments
#   winetricks     Windows runtimes installed into the game's prefix
#   files          drop mod files into the game folder or Proton prefix
#   rawLaunchOptions  a classic "VAR=1 %command% -flag" string, as-is
#
# Caveat: anything set by hand in a game's Steam launch-options field gets
# overwritten once the game has an entry here, so move it into
# rawLaunchOptions first.
{
  programs.steam.config = {
    enable = true;

    apps = {
      # The two entries below are templates, not real config: `enable =
      # false` keeps them inert (nothing is applied, and nothing extra is
      # pulled into the build) but still type-checked on every rebuild, so
      # they can't rot. Copy one, change the App ID and name, and flip
      # `enable` on (or just delete the line).

      # A game that needs a specific Proton build.
      "413150" = {
        enable = true;
        name = "Stardew Valley";
        # compatTool = pkgs.proton-ge-bin;
        # Switching Proton builds doesn't reset the game's prefix. If a
        # game breaks after a switch, delete its prefix so it regenerates
        # (saves kept inside the prefix go with it).
      };

      # A game that needs a mod loader (BepInEx here). The loader is a
      # Windows DLL Wine wouldn't load by default, so it has to be told to
      # prefer the game folder's copy.
      # "1966720" = {
      #   enable = false;
      #   name = "Lethal Company";
      #   dllOverrides.winhttp = "n,b";
      #   # The mod files themselves are declared per path, relative to the
      #   # game's install folder, e.g. keep them in this repo and add:
      #   #   files.game.place."BepInEx/plugins/SomeMod.dll".source =
      #   #     ./steam/lethal-company/SomeMod.dll;
      #   # A directory source is copied recursively and merged, so an
      #   # unpacked mod loader can be dropped over the game root. Use
      #   # `mode = "seed"` on config files the game or you edit in place.
      # };
    };
  };
}

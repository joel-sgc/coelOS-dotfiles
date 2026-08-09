{ ... }:

{
  programs.ghostty = {
    enable = true;

    # ANSI 1-14 match ghostty's own bundled "Everforest Dark Hard" theme --
    # accent colors are identical across all Everforest contrast tiers
    # (per sainnhe/everforest's palette.md), only background/foreground
    # differ here, swapped to the Medium tier (see home/theme/everforest.nix).
    themes.everforest-dark-medium = {
      palette = [
        "0=#7a8478"
        "1=#e67e80"
        "2=#a7c080"
        "3=#dbbc7f"
        "4=#7fbbb3"
        "5=#d699b6"
        "6=#83c092"
        "7=#f2efdf"
        "8=#a6b0a0"
        "9=#f85552"
        "10=#8da101"
        "11=#dfa000"
        "12=#3a94c5"
        "13=#df69ba"
        "14=#35a77c"
        "15=#fffbef"
      ];
      background = "2d353b";
      foreground = "d3c6aa";
      "cursor-color" = "e69875";
      "cursor-text" = "4c3743";
      "selection-background" = "4c3743";
      "selection-foreground" = "d3c6aa";
    };

    settings = {
      theme = "everforest-dark-medium";
      "font-family" = "FiraCode Nerd Font Mono";
      "font-size" = 10;
      keybind = [
        "ctrl+t=new_tab"
        "ctrl+w=close_tab"
      ];
    };
  };
}

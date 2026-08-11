{ ... }:

let
  theme = import ./theme/onedark.nix;
in
{
  programs.ghostty = {
    enable = true;

    # Ghostty's own bundled "Atom One Dark" is the canonical Atom palette,
    # not tal7aouy's personally-tweaked values (bg #21252b vs this file's
    # #282c34, green #98c379 vs #89ca78, purple #c678dd vs #d55fde, cyan
    # #56b6c2 vs #2bbac5) -- close family, not an exact match, so hand-rolled
    # from the verified real values instead (same situation Everforest was
    # in). ANSI slots assigned by conventional role; 8-15 repeat 0-7 like
    # ghostty's own bundled themes do.
    themes.onedark-tal7aouy = {
      background = theme.bg;
      foreground = theme.fg;
      "cursor-color" = theme.blue;
      "cursor-text" = theme.bg;
      "selection-background" = theme.surface;
      "selection-foreground" = theme.fg;

      palette = [
        "0=${theme.bg}"
        "1=${theme.red}"
        "2=${theme.green}"
        "3=${theme.yellow}"
        "4=${theme.blue}"
        "5=${theme.purple}"
        "6=${theme.cyan}"
        "7=${theme.fg}"
        "8=${theme.comment}"
        "9=${theme.red}"
        "10=${theme.green}"
        "11=${theme.yellow}"
        "12=${theme.blue}"
        "13=${theme.purple}"
        "14=${theme.cyan}"
        "15=${theme.fg}"
      ];
    };

    settings = {
      theme = "onedark-tal7aouy";
      "font-family" = "FiraCode Nerd Font Mono";
      "font-size" = 10;
      keybind = [
        "ctrl+t=new_tab"
        "ctrl+w=close_tab"
      ];
    };
  };
}

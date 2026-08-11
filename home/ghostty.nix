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
        # Unbound rather than pointed at ghostty's own tab actions: ghostty
        # has no concept of "which program is running in this pane" to
        # switch behavior on, but `unbind` sends the key straight through to
        # whatever's actually running instead of consuming it here. Fresh's
        # keymap (home/fresh.nix) binds all three to its own tab/buffer
        # actions (close_tab / next_buffer / prev_buffer), so while Fresh is
        # open these three now do tab navigation *in Fresh*; falling through
        # to a plain shell just gets zsh's own readline behavior for them
        # (ctrl+w = delete word backward) instead of ghostty eating them
        # first.
        "ctrl+w=unbind"
        "ctrl+tab=unbind"
        "ctrl+shift+tab=unbind"
      ];
    };
  };
}

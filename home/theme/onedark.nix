# tal7aouy's "theme" VS Code extension (github.com/tal7aouy/theme), a personal
# One-Dark-family variant -- values verbatim from its real source
# (extension/src/utils/colors.ts + Theme.json's editor.background/
# button.background), not the canonical Atom One Dark (ghostty's bundled
# "Atom One Dark" and micro's bundled "one-dark.micro" are both that
# canonical variant, confirmed measurably different: e.g. bg #21252b/#21252C
# vs this file's #282c34, purple #c678dd vs #d55fde, green #98c379 vs
# #89ca78).
{
  bg = "#282c34";
  surface = "#404754"; # button.background -- elevated/container tone
  fg = "#abb2bf"; # lightWhite
  comment = "#5c6370"; # their "dark" -- confusingly named, it's the muted/comment grey

  red = "#ef596f"; # coral -- their signature "variable" color
  error = "#f44747"; # explicit "error" role in their own colors.ts, distinct from coral
  orange = "#d19a66"; # whiskey
  yellow = "#e5c07b"; # chalky
  green = "#89ca78";
  cyan = "#2bbac5"; # fountainBlue
  blue = "#61afef"; # malibu
  purple = "#d55fde";
}

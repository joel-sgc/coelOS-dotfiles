{ lib, pkgs, ... }:

let
  theme = import ../home/theme/onedark.nix;

  # "#rrggbb" -> "r,g,b" (decimal), the form kmscon's palette-* keys take.
  hexDigit = c: lib.lists.findFirstIndex (x: x == c) null (lib.stringToCharacters "0123456789abcdef");
  hexByte = s: hexDigit (builtins.substring 0 1 s) * 16 + hexDigit (builtins.substring 1 1 s);
  rgb =
    hex:
    let
      h = lib.toLower (lib.removePrefix "#" hex);
    in
    lib.concatMapStringsSep "," (i: toString (hexByte (builtins.substring i 2 h))) [ 0 2 4 ];
  # libtsm (kmscon's terminal emulation) drops modifiers a Ghostty-style zsh
  # setup relies on: Ctrl+Shift+Left/Right arrive as plain Ctrl+Left/Right
  # (Ctrl is checked first), and Ctrl+Backspace/Delete as plain Backspace/
  # Delete. The patch sends xterm's sequences instead (\e[1;6D/C, \e[3;5~)
  # and ^H for Ctrl+Backspace, matching the binds in home/zsh/init.sh.
  libtsm-patched = pkgs.libtsm.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./tty-libtsm-keys.patch ];
  });
in
{
  # kmscon replaces the kernel VT on the autovt TTYs (Ctrl+Alt+F3 etc.). The
  # kernel console only does bitmap fonts and a 16-color palette, so it can't
  # draw Nerd Font glyphs (starship prompt) or match Ghostty. The greetd
  # login screen is separate and unaffected.
  services.kmscon = {
    enable = true;
    package = pkgs.kmscon.override { libtsm = libtsm-patched; };
    # Same layout as the rest of the system (services.xserver.xkb).
    useXkbConfig = true;
    fonts = [
      {
        name = "FiraCode Nerd Font Mono"; # same family as home/ghostty.nix
        package = pkgs.nerd-fonts.fira-code;
      }
    ];
    # Same slot assignment as home/ghostty.nix: 8-15 repeat 0-7, with
    # the comment grey as the bright black.
    extraConfig = ''
      font-size=12
      palette=custom
      palette-background=${rgb theme.bg}
      palette-foreground=${rgb theme.fg}
      palette-black=${rgb theme.bg}
      palette-red=${rgb theme.red}
      palette-green=${rgb theme.green}
      palette-yellow=${rgb theme.yellow}
      palette-blue=${rgb theme.blue}
      palette-magenta=${rgb theme.purple}
      palette-cyan=${rgb theme.cyan}
      palette-light-grey=${rgb theme.fg}
      palette-dark-grey=${rgb theme.comment}
      palette-light-red=${rgb theme.red}
      palette-light-green=${rgb theme.green}
      palette-light-yellow=${rgb theme.yellow}
      palette-light-blue=${rgb theme.blue}
      palette-light-magenta=${rgb theme.purple}
      palette-light-cyan=${rgb theme.cyan}
      palette-white=${rgb theme.fg}
    '';
  };
}

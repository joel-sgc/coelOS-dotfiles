{ ... }:

let
  theme = import ./theme/onedark.nix;
in
{
  programs.netpala = {
    enable = true;

    settings = {
      colors = {
        primary = "${theme.blue}";
        active = "${theme.purple}";

        # primary = "#a7abca"        # Light blue-gray

        # # Active/selected borders
        # active = "#9cca69"         # Green

        # # Active/selected text
        # active_text = "#cda162"    # Orange

        # # Selection bar background
        # selection_bg = "#5a6988"   # Darker blue-gray

        # # Inactive/dimmed elements
        # inactive = "#444a66"       # Dark gray

        # # Error states
        # error = "#ff0000"          # Red

        # # Error text
        # error_text = "#aa0000"     # Dark red

        # # Helper text at the bottom of the window
        # help_text = "#a7abca"      # Light blue-gray
      };
      keybindings = {
        quit.keys = [
          "q"
          "ctrl+c"
        ];
        scan.keys = [ "s" ];
      };
    };
  };
}

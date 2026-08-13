{ ... }:

let
  theme = import ./theme/onedark.nix;
in
{
  programs.bluepala = {
    enable = true;

    settings = {
      colors = {
        primary = "${theme.fg}";
        active = "${theme.green}";
        active_text = "${theme.yellow}";
        error = "${theme.red}";
        error_text = "${theme.red}";
        selection_bg = "${theme.fg}";
        help_text = "${theme.fg}";

        # primary = "#a7abca"        # Light blue-gray
        # active = "#9cca69"         # Green
        # active_text = "#cda162"    # Orange
        # selection_bg = "#5a6988"   # Darker blue-gray
        # inactive = "#444a66"       # Dark gray
        # error = "#ff0000"          # Red
        # error_text = "#aa0000"     # Dark red
        # help_text = "#a7abca"      # Light blue-gray
      };
    };
  };
}

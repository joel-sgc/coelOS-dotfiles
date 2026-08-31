{ config, pkgs, ... }:

{
  # Auto-switches monitor layout profiles based on which outputs are
  # currently connected. No profiles defined yet -- kanshi runs fine with
  # none (just idles). To add one: run `hyprctl monitors` for real output
  # names, then set services.kanshi.settings; see home-manager's kanshi
  # module docs.
  services.kanshi.enable = true;
}

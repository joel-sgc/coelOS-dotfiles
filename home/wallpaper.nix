{ config, pkgs, ... }:

{
  # Wallpaper daemon. `swww` was renamed upstream to `awww`; this is the
  # same tool your old Arch config used (as `swww`/`swww-daemon`).
  #
  # Daemon only for now — no wallpaper image or the old 30min cycling script
  # ported yet, since that needs the actual image assets pulled over from
  # the old dotfiles repo. That's a theming-phase task.
  services.awww.enable = true;
}

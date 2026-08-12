{ ... }:

{
  # Plasma-side counterpart to home/wallpaper.nix's coel-random-wallpaper:
  # Hyprland gets it via an exec-once entry (home/hyprland.nix), which has
  # no equivalent under Plasma. XDG autostart is the actual "once per
  # session login" hook Plasma provides -- entries in ~/.config/autostart
  # run once each time a Plasma session starts, matching "randomized every
  # relog" for KDE the same way exec-once does for Hyprland.
  #
  # `OnlyShowIn=KDE;` because nothing here should also try to run this
  # under Hyprland -- Hyprland doesn't scan XDG autostart entries at all
  # (home/hyprland.nix uses explicit exec-once instead), but this is the
  # same "don't leak across sessions" precaution already taken for the
  # Wayland services in home/hyprland.nix (wayland.systemd.target).
  xdg.configFile."autostart/coel-random-wallpaper.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Random Wallpaper
    Comment=Applies a random wallpaper from ~/Pictures/wallpapers on login
    Exec=coel-random-wallpaper
    OnlyShowIn=KDE;
    X-KDE-autostart-phase=1
    NoDisplay=true
  '';
}

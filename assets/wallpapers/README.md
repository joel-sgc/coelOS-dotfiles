# Wallpapers

The images in this folder are the `misc/` set from
[Narmis-E/onedark-wallpapers](https://github.com/Narmis-E/onedark-wallpapers),
vendored here (not a git submodule) so the NixOS config stays
self-contained and reproducible without a network dependency at build
time. `LICENSE` is that repo's license, copied alongside for
attribution.

Wired up in `home/wallpaper.nix` (`coel-random-wallpaper`, symlinked
into `~/Pictures/wallpapers`) — picks a random image from this set on
every Hyprland session start. See that file for the hookup.

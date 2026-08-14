# recolor-plymouth-theme.sh

Recolors the CoelOS Plymouth boot-splash assets — the lock icon, password
entry field, password-dot bullet, and progress bar/track, plus the
ascii-art logo — to a new set of colors in one shot.

## Usage

```
recolor-plymouth-theme.sh [--logo COLOR] [--accent COLOR] [--track COLOR]
```

| Flag       | Default   | Applies to                                    |
|------------|-----------|------------------------------------------------|
| `--logo`   | `#61afef` | `logo.png` (the "COELOS" wordmark)             |
| `--accent` | `#e5c07b` | `bullet.png`, `entry.png`, `lock.png`, `progress_bar.png` |
| `--track`  | `#404754` | `progress_box.png`                             |

The defaults are the palette currently live in the boot theme (One Dark's
`theme.blue`/`theme.yellow`/`theme.surface` — see
`home/theme/onedark.nix`). Running it with no arguments is idempotent: it
regenerates the assets already in place, byte-different (PNG re-encoding)
but pixel-identical.

**`--accent` and `--track` must be different colors.** `progress_box.png`
is the static track and `progress_bar.png` is the fill that gets scaled
wider as boot progresses (see `coelos-theme/coelos.script`'s
`update_progress_bar`); if both are the same color the growing bar is
invisible against its own track.

Example — try a purple/green scheme without touching the real theme:

```
./recolor-plymouth-theme.sh --logo '#d55fde' --accent '#89ca78' --track '#282c34'
```

## How it works

Two different techniques, depending on the asset:

- **`bullet`/`entry`/`lock`/`progress_bar`/`progress_box`**: these are
  flat single-color PNGs — inspecting their pixel histograms shows every
  opaque pixel is the *same* RGB value, with all shape/edge detail
  (anti-aliasing, rounded corners) encoded entirely in the **alpha**
  channel. So each one is recolored by extracting its alpha channel,
  flooding a same-size canvas with the target color, and recompositing
  the extracted alpha back on top (`-compose CopyOpacity`). The result is
  bit-for-bit the same shape with a different flat color — there's no
  gradient or lightness variation to preserve, because none existed in
  the original.
- **`logo.png`**: regenerated from scratch by calling `generate-logo.sh`
  against `coelos-dotfiles/ascii-name.txt` (see `generate-logo.md`),
  rather than recoloring the existing PNG. Same end result, since that
  script also produces a single flat color, but it means the logo doesn't
  depend on a previous PNG existing at all.

Alpha shapes for the first group are always read from `coelos-theme/` (the
repo-root copy), regardless of which output directory is currently being
written — safe because the script only ever reads alpha from there and
never modifies it mid-run.

### Why not GIMP?

An earlier version of this workflow was done by hand in GIMP, using its
"Colorize" tool. Scripting that in GIMP 3's batch/Script-Fu mode turned
out to be unreliable here — GIMP 3 renamed large parts of the PDB that
GIMP 2.10's Script-Fu exposed (e.g. `gimp-image-get-active-drawable` no
longer exists), so procedure names had to be rediscovered by trial and
error rather than trusted from memory. The ImageMagick approach above
produces the identical visual result (verified pixel-for-pixel against
the alpha data) without depending on that shifting API.

## Output

Writes to **both**:

- `coelos-theme/` (repo root) — the actual source `configuration.nix`'s
  `boot.plymouth` builds the live theme from.
- `coelos-dotfiles/configs/plymouth/` — a reference/backup copy, kept in
  sync purely for consistency (`coelos-dotfiles/` is gitignored from the
  main repo, so this copy isn't tracked either way).

## Requirements

- ImageMagick's `magick` and `identify` in `PATH`.
- `generate-logo.sh` in the same directory as this script.
- `coelos-dotfiles/ascii-name.txt` (one level up from this script).
- Invoke with `bash recolor-plymouth-theme.sh ...`, or run it directly —
  unlike `generate-logo.sh`, this one's `#!/usr/bin/env bash` shebang
  works fine on NixOS.

## Applying changes

This script only touches files in the repo working tree — it doesn't
rebuild or activate anything. After running it:

```
nix build .#nixosConfigurations.coelos.config.system.build.toplevel
```

to verify, then `sudo nixos-rebuild switch` to apply. Plymouth only draws
once during the boot sequence, so the new colors won't be visible until
your *next* boot, even right after switching.

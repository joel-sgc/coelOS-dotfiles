# generate-logo.sh

Rasterizes a block-character ASCII-art file into a transparent PNG, by
drawing one filled rectangle per non-space character. This is how
`coelos-theme/logo.png` (the CoelOS wordmark shown by the Plymouth boot
splash) is produced from `coelos-dotfiles/ascii-name.txt`.

## Usage

```
generate-logo.sh INPUT.txt OUTPUT.png [COLOR]
```

- `INPUT.txt` — a plain-text file where each non-space character becomes
  one filled cell in the output image. Line length and line count
  determine the canvas size, so the file doesn't need to be padded to a
  rectangle; ragged line lengths just leave the missing cells blank.
- `OUTPUT.png` — where to write the rasterized PNG. Background is fully
  transparent (`xc:none`); only the character cells are painted.
- `COLOR` — any ImageMagick color spec (`#61afef`, `rgb(97,175,239)`,
  `blue`, ...). Defaults to `black` if omitted.

```
./generate-logo.sh ../ascii-name.txt /tmp/logo.png "#61afef"
```

## How it works

Each character cell is a fixed `5x10` px rectangle (`CELL_W`/`CELL_H` at
the top of the script). The script measures the input's width in
characters (longest line) and height in lines, multiplies by the cell
size to get the canvas dimensions, then walks the file character by
character: every non-space character adds one
`-draw "rectangle x1,y1 x2,y2"` to a single ImageMagick command, filled
with `COLOR`. The whole thing executes as one `magick` invocation at the
end.

Because it's a flat rectangle fill with no anti-aliasing, blur, or
gradient, the output is always a single flat color at full opacity
wherever a character was — there's no shading to preserve, which is why
`recolor-plymouth-theme.sh` (see `recolor-plymouth-theme.md`) calls this
script directly to regenerate the logo in a new color, rather than
recoloring the existing `logo.png` in place the way it does for the other
Plymouth assets.

## Requirements

- `bash` — invoke it as `bash generate-logo.sh ...`, not `./generate-logo.sh`.
  Its shebang is `#!/usr/bin/bash`, which doesn't exist on NixOS (no FHS
  `/usr/bin`), so direct execution fails with "bad interpreter."
- ImageMagick's `magick` command in `PATH`.

## Source data

- `coelos-dotfiles/ascii-name.txt` — the "COELOS" wordmark (what
  `logo.png` is actually generated from).
- `coelos-dotfiles/ascii-logo.txt` — a separate, more detailed pictorial
  mark. Its content (not the file itself) was copied inline into
  `home/fastfetch.nix`'s `xdg.configFile."fastfetch/ascii-logo.txt"` for
  the fastfetch "About" popup; this script isn't involved in producing
  that one, since fastfetch renders it as text directly rather than a PNG.

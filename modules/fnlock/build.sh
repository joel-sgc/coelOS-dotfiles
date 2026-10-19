#!/usr/bin/env bash
# Build the Framework 13 AMD 7040 EC firmware in a container.
#
#   ./build.sh                 # stock image (should match your laptop's EC)
#   ./build.sh patches/fn-state-events.patch   # with patches applied
#
# Output: ./work/out/ec.bin
# Needs podman (preferred on NixOS) or docker.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
engine=$(command -v podman || command -v docker || { echo "need podman or docker" >&2; exit 1; })

mkdir -p "$here/work/patches"
rm -f "$here/work/patches/"*.patch
i=0
for p in "$@"; do
    i=$((i + 1))
    cp "$p" "$here/work/patches/$(printf '%02d' "$i")-$(basename "$p")"
done

"$engine" build -t fw13-ec-builder -f "$here/Containerfile" "$here"
"$engine" run --rm -v "$here/work:/work:Z" fw13-ec-builder
echo "Built: $here/work/out/ec.bin"

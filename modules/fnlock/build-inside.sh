#!/usr/bin/env bash
# Runs inside the container. /work is a host directory mounted in.
#   /work/patches/*.patch  - optional patches applied to the EC tree, in order
#   /work/out/             - build output lands here
set -euo pipefail

EC_COMMIT=${EC_COMMIT:-cf6b79c7d8cf0ee1c5716fa27271c0b37a534580}   # your BIOS 3.16 EC
ZEPHYR_COMMIT=${ZEPHYR_COMMIT:-7b88e177ba900ce45495a7a49af7148baf3348ee}
# Framework's build used a ChromiumOS mirror commit (4aa3ff) that is not on
# GitHub; this is the revision Zephyr itself pins, and it builds the same image.
CMSIS_COMMIT=${CMSIS_COMMIT:-74981bf893e8b10931464b9945e2143d99a3f0a3}

fetch() {  # fetch <dir> <url> <commit> [extra clone args]
    local dir=$1 url=$2 commit=$3; shift 3
    if [ ! -d "$dir/.git" ]; then
        git clone -q "$@" --no-checkout "$url" "$dir"
    fi
    git -C "$dir" fetch -q origin "$commit" 2>/dev/null || true
    git -C "$dir" -c advice.detachedHead=false checkout -q -f "$commit"
    git -C "$dir" clean -qfdx
}

cd /work
echo ">> fetching sources"
# Blobless (not shallow) so the version string's commit count is right.
fetch src/ec     https://github.com/FrameworkComputer/EmbeddedController "$EC_COMMIT" --filter=blob:none
fetch src/zephyr https://github.com/FrameworkComputer/zephyr             "$ZEPHYR_COMMIT" --filter=blob:none -b lotus-zephyr
fetch src/cmsis  https://github.com/zephyrproject-rtos/cmsis             "$CMSIS_COMMIT" --filter=blob:none

mkdir -p modules
ln -sfn /work/src/cmsis modules/cmsis
ln -sfn /work/src/ec    modules/ec

shopt -s nullglob
for p in /work/patches/*.patch; do
    echo ">> applying $(basename "$p")"
    git -C src/ec apply --verbose "$p"
done

pip install -q --no-cache-dir /work/src/ec/zephyr/zmake

echo ">> building azalea"
cd src/ec
zmake --zephyr-base /work/src/zephyr --modules-dir /work/modules \
      -j"$(nproc)" build azalea -t zephyr

mkdir -p /work/out
cp build/zephyr/azalea/output/ec.bin /work/out/ec.bin
cp build/zephyr/azalea/output/zephyr.ro.elf build/zephyr/azalea/output/zephyr.rw.elf /work/out/
echo ">> done"
sha256sum /work/out/ec.bin
strings /work/out/ec.bin | grep -m1 'azalea_v.*cmsis' || true

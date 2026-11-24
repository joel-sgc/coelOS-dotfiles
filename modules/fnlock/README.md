# Fn lock detection for the Framework Laptop 13 (AMD 7040)

Fn lock (Fn+Esc) lives entirely in the embedded controller (EC). This patches the EC
firmware so that:

1. A new host command `0x3EF0` returns the Fn / Fn lock bits (`fnlock-state.py` reads it).
2. Each Fn+Esc taps a key the keyboard can't otherwise produce: F13 when Fn lock turns
   on, F14 when it turns off. Linux remaps them to `KEY_PROG3` / `KEY_PROG4`.

Only the EC's **RW** slot is flashed; Framework's **RO** firmware is never touched and
stays as the fallback. Flashing EC firmware can brick a laptop: keep a backup, and never
flash RO.

Built against EC `azalea_v3.4.113388` (BIOS 03.16), source
[FrameworkComputer/EmbeddedController](https://github.com/FrameworkComputer/EmbeddedController)
@ `cf6b79c7`, zephyr @ `7b88e177`. Building, RW flashing, the state query and the F13/F14
events are tested; `nixos/ec-jump-rw.nix` is **untested**.

## Files

| File | Purpose |
|---|---|
| `patches/fn-state-events.patch` | The EC change (host command + toggle key events), in `zephyr/program/framework/` (`azalea/src/keyboard_customization.c`, `include/board_host_command.h`) |
| `Containerfile`, `build.sh`, `build-inside.sh` | Reproducible EC build in an Ubuntu container (podman/docker) |
| `fnlock-state.py` | Reads the state from `/dev/cros_ec`; `--json`, `--watch` |
| `nixos/fnlock.nix` | hwdb key remap + `fnlockd` service writing `/run/fnlock/state` |
| `nixos/ec-jump-rw.nix` | Optional: jump back to RW at boot after an EC reset (untested) |

## Build and flash

```sh
./build.sh patches/fn-state-events.patch && cp work/out/ec.bin ec-fnevents.bin   # each build overwrites work/out/ec.bin
sudo framework_tool --dump-ec-flash ec-backup.bin       # once; keep it off the laptop and out of public repos
sudo framework_tool --versions                          # "Current image": RO or RW
sudo framework_tool --reboot-ec jump-ro                 # needed if running RW; REBOOTS the laptop
sudo framework_tool --flash-rw-ec ec-fnevents.bin --dry-run   # ends in "RW verify fail": expected
sudo framework_tool --flash-rw-ec ec-fnevents.bin             # must end "RW verify success", else stay on RO
sudo framework_tool --reboot-ec jump-rw                 # reboots; --versions should show RW + your build
```

Undo: `jump-ro`, or any Framework BIOS update (rewrites the whole EC). Never rewrite the
slot the EC is running from. Build errors seen: the container needs `gcc`,
`device-tree-compiler` and `python3-libfdt` from Ubuntu.

## TPM lockout after EC jumps

Every `jump-ro`/`jump-rw` is an unclean power-off, which the TPM counts as a possible
attack. Several in a row put it in dictionary-attack lockout, and anything that unseals
with the TPM then fails. Here that was libvirtd (`Failed to unseal secret using TPM2: No
locks available`, `0x921` = `TPM_RC_LOCKOUT`).

```sh
nix-shell -p tpm2-tools --run "sudo tpm2_getcap properties-variable" | grep -iE "inLockout|lockoutAuthSet|MAX_AUTH|LOCKOUT_"
nix-shell -p tpm2-tools --run "sudo tpm2_dictionarylockout --clear-lockout"   # then restart libvirtd
```

Clear the counter after every flashing session. If `lockoutAuthSet` is 1 and you don't
know the password, don't retry (it extends the lockout). **Never clear the TPM in the
BIOS**: it destroys every sealed key (libvirt credential, disk unlock).

## Using it

```sh
sudo python3 fnlock-state.py [--json|--watch]   # "EC returned error 1" = running firmware lacks the patch
```

Don't give your user access to `/dev/cros_ec` (it can also reflash the EC); read
`/run/fnlock/state` (written by `fnlockd`) instead. It is replaced atomically, so
`inotifywait -e moved_to /run/fnlock`, not the file. After enabling `nixos/fnlock.nix`,
`sudo udevadm trigger`, then check with `evtest` ("AT Translated Set 2 keyboard"):
Fn+Esc should give `KEY_PROG3` / `KEY_PROG4`; if `MSC_SCAN` isn't 64/65, update the hwdb.

## Persistence

- Survives OS reboots and shutdowns (battery keeps the EC on RW).
- Falls back to RO on a drained/disconnected battery or EC reset: `jump-rw` again (or
  `ec-jump-rw.nix`, which adds a TPM strike per automatic jump).
- Wiped by a Framework BIOS update.

Flashing RO too would make it permanent but removes the safety net; a bad RO needs a
hardware programmer to recover. Not recommended.

## After a BIOS update

1. `framework_tool --versions`, note the new `ec:<hash>` / `os:<hash>`.
2. Set `EC_COMMIT` / `ZEPHYR_COMMIT` in `build-inside.sh`, delete `work/src/ec`, rebuild.
   If the patch no longer applies, the Fn handling is in `keyboard_customization.c` (`FN_LOCKED`).
3. Update `EXPECTED_RW` in `nixos/ec-jump-rw.nix` if used, then flash as above.

Builds use CMSIS `74981b` (Zephyr's pin) instead of Framework's `4aa3ff`, and report
`113387` vs `113388`: both cosmetic.

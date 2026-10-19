# Fn lock detection for the Framework Laptop 13 (AMD 7040)

The Framework 13's Fn lock (toggled with Fn+Esc) is handled entirely inside the
embedded controller (EC), so the OS normally has no idea whether it's on.

This repo patches the EC firmware so that:

1. **The state can be queried.** A new EC host command (`0x3EF0`) returns the
   Fn / Fn lock bits. `fnlock-state.py` reads it.
2. **Toggles are announced.** Every Fn+Esc taps a key the keyboard can't
   otherwise produce: the F13 scancode when Fn lock turns **on**, F14 when it
   turns **off**. Linux sees a normal key event, which is remapped to
   `KEY_PROG3` / `KEY_PROG4` and can be bound to anything.

Only the EC's **RW** slot is flashed. Framework's original **RO** firmware is
never touched and stays as a fallback.

> ⚠️ Flashing EC firmware can make a laptop unbootable. Read the whole
> document before flashing anything, and keep a backup of your EC.
>
> ⚠️ Every `jump-ro` / `jump-rw` cuts power abruptly, which counts against the
> TPM's anti-brute-force limit. Several in a row can lock the TPM and break
> anything that unseals secrets with it (libvirtd did here). See
> [TPM lockout](#tpm-lockout-after-ec-jumps).

## Status

| Item | Value |
|---|---|
| Laptop | Framework Laptop 13, AMD Ryzen 7040 (`azalea`), mainboard `MassProduction` |
| BIOS | 03.16 (07/25/2025) |
| Factory EC | `azalea_v3.4.113388-ec:cf6b79,os:7b88e1,cmsis:4aa3ff` |
| EC source | [FrameworkComputer/EmbeddedController](https://github.com/FrameworkComputer/EmbeddedController) @ `cf6b79c7d8cf0ee1c5716fa27271c0b37a534580` |
| Zephyr | [FrameworkComputer/zephyr](https://github.com/FrameworkComputer/zephyr) @ `7b88e177ba900ce45495a7a49af7148baf3348ee` (`lotus-zephyr`) |
| CMSIS | [zephyrproject-rtos/cmsis](https://github.com/zephyrproject-rtos/cmsis) @ `74981bf893e8b10931464b9945e2143d99a3f0a3` (see notes) |
| Tested on | NixOS, kernel 6.18, `framework_tool` 0.6.3 |

Tested and working: building, RW flashing, the state query, and the
F13/F14 events. `nixos/ec-jump-rw.nix` is **untested**.

## Files

| File | Purpose |
|---|---|
| `patches/fn-state-events.patch` | The EC change (host command + toggle key events) |
| `Containerfile`, `build.sh`, `build-inside.sh` | Reproducible EC build in an Ubuntu container (podman or docker) |
| `fnlock-state.py` | Reads the state from `/dev/cros_ec`; `--watch` mode for a service |
| `nixos/fnlock.nix` | Key remap (hwdb) + `fnlockd` service writing `/run/fnlock/state` |
| `nixos/ec-jump-rw.nix` | Optional: jump back to RW at boot after an EC reset (untested) |

## What the patch does

All changes are in `zephyr/program/framework/`:

- `include/board_host_command.h`: defines `EC_CMD_GET_FN_STATE` (`0x3EF0`),
  returning one byte: bit 0 = Fn held, bit 1 = Fn lock on.
- `azalea/src/keyboard_customization.c`:
  - implements that host command by reading the existing `Fn_key` variable;
  - in the Fn+Esc handler, after the lock bit flips, calls the EC's existing
    `simulate_keyboard()` helper (the one used for Fn+B → Break) to tap set-2
    scancode `0x08` (F13) for "locked" or `0x10` (F14) for "unlocked".

Neither scancode is in this keyboard's matrix, so nothing clashes. The keys are
only sent while the laptop is awake, which is the only time Fn+Esc can be
pressed anyway.

## Building

Requires podman (NixOS: `virtualisation.podman.enable = true;`) or docker.

```sh
./build.sh                                  # stock firmware (sanity check)
cp work/out/ec.bin ec-stock.bin

./build.sh patches/fn-state-events.patch    # patched firmware
cp work/out/ec.bin ec-fnevents.bin
```

Each build overwrites `work/out/ec.bin`, so copy it out. A successful build
ends with `>> done`, a SHA-256 and a version line such as
`azalea_v3.4.113387-ec:cf6b79,os:7b88e1,cmsis:74981b <date> root@<container>`.
Sources are cached in `work/src`, so rebuilds are quick.

To target a different EC version, set `EC_COMMIT` / `ZEPHYR_COMMIT` in
`build-inside.sh` (see "After a BIOS update").

## Flashing

All commands need root. On this machine `framework_tool` triggers the
fingerprint prompt via sudo.

### 1. Back up the EC (once)

```sh
sudo framework_tool --dump-ec-flash ec-backup.bin
strings ec-backup.bin | grep azalea_v     # should show Framework's build string
```

Keep `ec-backup.bin` off the laptop and **out of public repos**.

### 2. Check what's running

```sh
sudo framework_tool --versions
```

Look at `Current image:` (RO or RW) and `Build version:`.

### 3. Flash RW

Never rewrite the slot the EC is running from. If `Current image` is RW,
switch to RO first (this **reboots the laptop**, so save your work):

```sh
sudo framework_tool --reboot-ec jump-ro
```

Then:

```sh
sudo framework_tool --flash-rw-ec ec-fnevents.bin --dry-run
sudo framework_tool --flash-rw-ec ec-fnevents.bin
```

- The dry run ends with `RW verify fail!`. **That's expected**: it skips the
  write but still compares against the chip. Everything before it should pass.
- The real run must end with `RW verify success`. If it doesn't, **don't jump
  to RW**; you're still safely on RO.

### 4. Run the new firmware

```sh
sudo framework_tool --reboot-ec jump-rw     # reboots the laptop
sudo framework_tool --versions              # Current image: RW, your build string
```

### Undo

```sh
sudo framework_tool --reboot-ec jump-ro     # back to Framework's RO firmware
```

A Framework BIOS update also restores factory EC firmware entirely.

### After a flashing session

Each jump in steps 3–4 is an unclean power-off. Once you're done, check and
reset the TPM's lockout counter (see the next section) so the strikes don't
add up:

```sh
nix-shell -p tpm2-tools --run "sudo tpm2_getcap properties-variable" | grep -iE "inLockout|lockoutAuthSet|MAX_AUTH|LOCKOUT_"
nix-shell -p tpm2-tools --run "sudo tpm2_dictionarylockout --clear-lockout"
```

## TPM lockout after EC jumps

### What happens

`--reboot-ec jump-ro` / `jump-rw` power the computer off without a proper
shutdown. The TPM (AMD's firmware TPM in the CPU, which the EC firmware does
**not** touch) treats an unclean shutdown as a possible attack whenever
protected keys were in use, and increments its lockout counter. After enough
strikes it enters **dictionary-attack lockout** and refuses to use protected
keys for a while.

Anything that unseals secrets with the TPM then fails. On NixOS, libvirtd
stores a systemd credential encrypted with the TPM and won't start:

```
Esys_Load() Esys Finish ErrorCode (0x00000921)
libvirtd.service: Failed to unseal secret using TPM2: No locks available
libvirtd.service: Main process exited, code=exited, status=243/CREDENTIALS
```

`0x921` is `TPM_RC_LOCKOUT`; "No locks available" (error 37) is systemd's
wording for the same thing. TPM-based disk unlock can be affected the same way.

This was triggered after one session of several `jump-ro`/`jump-rw` cycles
(flashing stock, then two patched builds).

### Check

```sh
nix-shell -p tpm2-tools --run "sudo tpm2_getcap properties-variable" | grep -iE "inLockout|lockoutAuthSet|MAX_AUTH|LOCKOUT_"
```

- `inLockout: 1`: locked out right now.
- `TPM2_PT_LOCKOUT_COUNTER`: current strikes. Lockout starts at `MAX_AUTH_FAIL`.
- `TPM2_PT_LOCKOUT_INTERVAL`: seconds per strike forgiven. It's `0x3E8`
  (1000 s, ~17 min) on this machine, so lockout clears by itself eventually.
- `lockoutAuthSet: 0`: the lockout password is empty (the default), so the
  reset below is safe.

Warnings about `tabrmd` / `TCTI` are harmless: the tools fall back to talking
to `/dev/tpmrm0` directly.

### Fix

```sh
nix-shell -p tpm2-tools --run "sudo tpm2_dictionarylockout --clear-lockout"
sudo systemctl restart libvirtd
```

- If `lockoutAuthSet` is **1** (a lockout password is set) and you don't know
  it, **don't retry** the clear. Wrong lockout passwords trigger a much longer
  lockout. Just wait for the counter to drain.
- **Don't clear the TPM in the BIOS.** It fixes the lockout but destroys every
  key in the TPM: libvirt's credential, TPM disk unlock, and anything else
  sealed to it.

### Avoiding it

- Space out jumps and reset the counter after a flashing session.
- `nixos/ec-jump-rw.nix` does an automatic abrupt jump at boot after an EC
  reset. That's rare, but each one is another strike.
- The EC supports a "jump on next shutdown" reboot flag that would make the
  switch during a clean shutdown. `framework_tool` 0.6.3 doesn't expose it, and
  it's untested on this EC.

## Using it

### Query the state

```sh
sudo python3 fnlock-state.py            # locked / unlocked
sudo python3 fnlock-state.py --json     # waybar-style JSON
sudo python3 fnlock-state.py --watch    # print on every change
```

`EC returned error 1` means the running firmware doesn't have the patch
(you're on RO or stock RW).

Don't give your user access to `/dev/cros_ec` to avoid sudo: that device can
also reflash the EC. Use the `fnlockd` service, which publishes the state to
`/run/fnlock/state` for everyone to read.

### NixOS

In `configuration.nix`:

```nix
imports = [
  ./path/to/fw13-fnlock/nixos/fnlock.nix
  # ./path/to/fw13-fnlock/nixos/ec-jump-rw.nix   # optional, see below
];
```

Rebuild, then `sudo udevadm trigger` (or reboot). Check with
`nix-shell -p evtest --run "sudo evtest"` (device "AT Translated Set 2
keyboard"): Fn+Esc should produce `KEY_PROG3` (locked) and `KEY_PROG4`
(unlocked). If the `MSC_SCAN` values aren't `64`/`65`, update `fnlock.nix`.

### KDE shortcuts (manual)

System Settings → Keyboard → Shortcuts → Add New → Command or Script:

- **Fn lock on**: `notify-send -t 1500 -a "Fn lock" "Fn lock ON"`, recorded
  by pressing Fn+Esc so it captures Prog3.
- **Fn lock off**: same with "OFF", capturing Prog4.

Each Fn+Esc toggles, so recording one shortcut per press gives you both.

### Reacting to the state file

```sh
while inotifywait -qq -e moved_to /run/fnlock; do
  notify-send "Fn lock $(cat /run/fnlock/state)"
done
```

The file is replaced atomically, so watch the directory, not the file.

## Persistence

- **Survives:** OS reboots and shutdowns. The EC stays powered by the battery
  and keeps running RW. Verify this on your machine with `--versions` after a
  reboot and after a full shutdown.
- **Falls back to Framework's RO:** a fully drained or disconnected battery, or
  an EC reset. Fix with `sudo framework_tool --reboot-ec jump-rw`, or enable
  `nixos/ec-jump-rw.nix` to do it at boot (one extra reboot; has a loop guard;
  untested; each automatic jump is an unclean power-off that counts toward
  [TPM lockout](#tpm-lockout-after-ec-jumps)).
- **Wiped:** by a Framework BIOS update, which rewrites the whole EC.

Flashing RO as well (`--flash-ro-ec ... --force`) would make it fully
permanent but removes the safety net. The RO half of the build has never
been run, and a bad RO can only be recovered with a hardware programmer
(e.g. a Bus Pirate with Framework's
[FrameworkDebugger](https://github.com/FrameworkComputer/FrameworkDebugger)
scripts). Not recommended without tested recovery hardware.

## After a BIOS update

1. `sudo framework_tool --versions` and note the new EC build string:
   `ec:<hash>` and `os:<hash>`.
2. Find the full commits in the EmbeddedController and zephyr repos, and set
   `EC_COMMIT` / `ZEPHYR_COMMIT` in `build-inside.sh`.
3. Delete `work/src/ec` (or let the script fetch the new commit), then rebuild
   with the patch. If it no longer applies, the Fn handling is in
   `azalea/src/keyboard_customization.c` (look for `FN_LOCKED`).
4. Update `EXPECTED_RW` in `nixos/ec-jump-rw.nix` if you use it.
5. Flash as above.

## Notes and caveats

- **CMSIS:** Framework's build used CMSIS commit `4aa3ff`, which only exists on
  Google's ChromiumOS mirror. These builds use `74981b`, the revision Zephyr
  itself pins. CMSIS is ARM header files; no issues seen.
- **Version number:** builds report `v3.4.113387` vs. Framework's `113388`. It's
  a commit count and purely cosmetic, and it's handy for telling builds apart.
- **Dry-run "verify fail"** is expected, see above.
- **Build errors** fixed along the way: the container needs `gcc` (binman
  preprocesses the device tree), `device-tree-compiler`, and `python3-libfdt`
  from Ubuntu (pip can't build `pylibfdt` without a compiler).
- **Upstream:** a similar HID-based approach for Intel boards is
  [EmbeddedController PR #55](https://github.com/FrameworkComputer/EmbeddedController/pull/55).

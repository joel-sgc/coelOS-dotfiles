# Home partition migration — remaining steps

Goal: move `/home/joelsgc` off the root partition onto its own LUKS-encrypted
partition (`nvme0n1p3`), so a future reinstall doesn't touch it and you never
have to re-sign into anything again.

Run everything below from a TTY (`Ctrl+Alt+F3`), logged out of the
graphical session, so nothing in your home directory is actively changing
while it's being copied.

## Status so far

- [x] `sudo cryptsetup luksFormat /dev/nvme0n1p3` — done (had to close a
      leftover mapping from the earlier inspection step first)
- [x] Got the new LUKS UUID via `blkid`: `2ad05545-2e7b-4191-93ad-3f654549bb9d`
- [x] `hardware-configuration.nix` updated with the `boot.initrd.luks.devices`
      and `fileSystems."/home"` entries — **already committed to the repo,
      but do NOT run `nixos-rebuild switch` or reboot yet.** See the warning
      in step 4.

## Step 1 — Open the new LUKS partition and format it with ext4

```
sudo cryptsetup luksOpen /dev/nvme0n1p3 luks-home
sudo mkfs.ext4 -L home /dev/mapper/luks-home
```

## Step 2 — Migrate your current home data onto it

```
sudo mount /dev/mapper/luks-home /mnt
sudo rsync -aHAX --info=progress2 /home/joelsgc/ /mnt/joelsgc/
```

## Step 3 — Verify the copy before trusting it

The first rsync attempt was incomplete (a diff afterward showed ~58 entire
top-level directories missing from the copy, including `.ssh`/`.config`/
`Documents`/`.nixos` — a real problem, not just noise). The second,
verbose re-run fixed it: a clean diff afterward showed only VS Code/Plasma
caches, logs, `.histfile`, and the diff-output scratch files themselves —
all expected. One leftover from the bad first attempt needed clearing: a
stray nested `/mnt/joelsgc/joelsgc/` directory (rsync run without a
trailing slash on the source at some point, copying the dir into itself).

```
sudo rm -rf /mnt/joelsgc/joelsgc   # only after confirming it's just a stray duplicate

sudo diff -rq /home/joelsgc /mnt/joelsgc > /tmp/diff-final.txt 2>&1
echo "exit code: $?"
wc -l /tmp/diff-final.txt
```

(Writing outside both trees avoids the diff-output-file-referencing-itself
noise. `diff` exit code `1` just means "differences found" — expected here
as long as they're all the benign cache/log/session-state kind. `2` means a
real error.)

If that comes back clean (same handful of benign entries, no missing
`.ssh`/`.config`/`Documents`/etc.), you're good. If anything looks wrong,
**stop here** — don't proceed to step 4 — and come back with what it showed.

Update: the diff (saved to `diff-final.txt` in the repo instead of `/tmp` —
still worked fine) came back as 16,689 lines, which looked alarming but
wasn't. Breakdown: 16,653 were `diff: <path>: No such file or directory` —
`diff` failing to stat-follow pre-existing broken symlinks (dead Python venv
interpreter links, stale Android JNI lib symlinks, cursor-theme symlinks
inside the old `~/backup/` snapshot), every single one referencing only
`/home/joelsgc`, never `/mnt/joelsgc` — these were already broken in the
source before any of this started, `rsync -a` correctly preserved them
as-is, and this says nothing about copy correctness. The remaining ~31
lines were all genuinely benign: live KDE services writing (`baloo` index,
`klipper` clipboard history + its sqlite WAL files), VS Code's own
caches/logs/session DBs, `.histfile`, this exact conversation's own
session transcript/log actively growing, and the scratch/runbook files
from this troubleshooting process itself. No `.ssh`/`Documents`/`Desktop`/
`Projects`/`Pictures`/`Downloads`/`.config`-or-`.nixos`-as-a-whole showed up
missing. **The nested `/mnt/joelsgc/joelsgc` stray directory was still
present in that run — make sure `rm -rf` actually ran before treating this
as done.**

Right before rebooting (step 4), do one more quick incremental sync to
catch last-minute drift (`.histfile`, session logs, etc. — cheap since
rsync only copies deltas on a re-run):
```
sudo rsync -aHAX /home/joelsgc/ /mnt/joelsgc/
```

Once you're confident, you can leave it mounted or:

```
sudo umount /mnt
sudo cryptsetup luksClose luks-home
```

## Step 4 — Rebuild and reboot

**Only do this once step 3 is verified.** The config change is already in
`hardware-configuration.nix` (both the `boot.initrd.luks.devices."luks-home"`
entry and `fileSystems."/home"`), so this step is just applying + rebooting:

```
sudo nixos-rebuild switch --flake ~/.nixos#coelos
sudo reboot
```

A newly-declared LUKS device only actually gets unlocked during initrd
(early boot), so `switch` alone won't engage the new mount for the current
session — you need the reboot. Expect two passphrase prompts during boot
(root, then home).

## Step 5 — Confirm after reboot

```
findmnt /home
```

Should show `/dev/mapper/luks-home`, not the root device. Check that your
files, browser sessions, SSH keys, etc. are all there and everything behaves
normally.

**Done** — confirmed `/home` is the new partition, and confirmed with a real
test (not just trusting the mount table) that the two are genuinely
independent: bind-mounted `/` read-only elsewhere, wrote a test file to the
live home, confirmed it did *not* appear in the old copy underneath. Mount
independence is proven.

## Step 6 — Cleanup (waiting a few days first, on purpose)

The old copy of `/home/joelsgc` is still sitting on the root partition,
hidden underneath the new mount. Deliberately holding off on deleting it —
decided to wait a few days of normal use as a safety net before reclaiming
it, rather than deleting right after the reboot. When you do come back to
this:

**Do not run `rm -rf /home/joelsgc` directly** — that path resolves through
the *new* mount now, so it would delete your current, live home directory,
not the old one. The old copy is only reachable via the same bind-mount
trick used for the independence test:

```
sudo mount --bind / /mnt
sudo mount -o remount,ro,bind /mnt
ls /mnt/home/joelsgc | head   # sanity check: this should be the OLD, pre-migration content
```

Once you're sure that's really the old copy and you're ready to reclaim the
space, remount read-write and delete:

```
sudo mount -o remount,rw,bind /mnt
sudo rm -rf /mnt/home/joelsgc
sudo umount /mnt
```

Then confirm the space came back on root:
```
df -h /
```

You can delete this file once cleanup is done.

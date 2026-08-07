# Hyprland migration

Plasma stays installed and selectable in SDDM for the entire migration — no phase here removes the fallback. See chat history for full rationale per phase.

## Phase 0 — safety net

- [x] Keep `services.desktopManager.plasma6` untouched throughout
- [x] Confirmed on `amdgpu` (good Wayland support, no driver fights)

## Phase 1 — bare compositor

- [x] `programs.hyprland.enable` in `configuration.nix`, alongside Plasma
- [x] `home/hyprland.nix` — monitors, basic keybinds, workspaces
- [x] Verified: logs in, terminal opens, workspaces switch, can exit back to SDDM
- [x] Natural scroll for trackpad (`input.touchpad.natural_scroll`)
- [x] 3-finger swipe between workspaces + `SUPER+#` (fixed: old `gestures.workspace_swipe*` was removed upstream in 0.51 — now uses the `gesture = 3, horizontal, workspace` directive)
- [x] Monitor scaling set to 1

## Phase 2 — daily-driver essentials

- [x] waybar installed + launches on start (`exec-once`)
- [x] rofi installed + `SUPER+Space` opens `rofi -show drun` (matches your old Omarchy-era keybind exactly)
- [ ] waybar/rofi actual styling/config (explicitly deferred for now — currently stock/unstyled)
- [x] Notifications daemon: **mako** (`home/mako.nix`), started via explicit `exec-once` in `home/hyprland.nix` rather than relying purely on D-Bus lazy-activation — deterministic startup, avoids any race with Plasma's own notifier
- [x] hyprlock + hypridle (`home/hypridle.nix`) — timings match the old config: lock at 5min, DPMS off at 10min, suspend at 20min; `SUPER+L` locks. `security.pam.services.hyprlock` added in `configuration.nix` (required or the password prompt can never succeed)
- [x] Wallpaper daemon: **awww** (`home/wallpaper.nix`) — `swww` was renamed upstream to `awww`, nixpkgs already reflects this. Daemon only for now; no image set and the old 30min-cycle script not ported yet since that needs the actual wallpaper assets pulled from the old dotfiles repo — theming-phase task
- [x] Volume/brightness OSD: **swayosd** (`home/swayosd.nix`), bound to `XF86Audio*`/`XF86MonBrightness*`. Needed system-level plumbing too: `services.udev.packages = [ pkgs.swayosd ]` + added `joelsgc` to the `video` group, so brightness writes work without root. Did _not_ wire up swayosd's libinput backend (a system-level service for raw CapsLock/ScrollLock events) since we don't need it — media keys are bound directly through Hyprland
- [x] Mouse-drag window move/resize: `bindm = SUPER, mouse:272, movewindow` / `mouse:273, resizewindow`
- [x] Window resize keybinds: `SUPER+SHIFT+arrows` → `resizeactive`, exact deltas from the old config
- [x] Window rules: `suppress-maximize-events` and `fix-xwayland-drags`
- [x] Clipboard: **cliphist** (`home/clipboard.nix`), `SUPER+V` → rofi picker piped through `cliphist decode | wl-copy`. History is plain text (`cliphist list`), readable/pipeable from anywhere including micro, not locked behind a GUI
- [x] Portals: replaced the flat `xdg.portal.config.common.default = "*"` with real per-desktop sections (`hyprland`/`kde`/`common`), matched against `$XDG_CURRENT_DESKTOP`, so screen-share/file-picker/etc. requests resolve to the actual running session's backend instead of racing on discovery order — the same class of fix as the systemd-target isolation below, just for portals. Turned out there are *two* separate `xdg.portal.config` namespaces (NixOS-level in `configuration.nix`, and a home-manager-level one that needed mirroring in `home/hyprland.nix` — the Hyprland HM module normally wires this automatically but skips it because we set `package = null`). Both fixed; verified by reading the actual generated `*-portals.conf` files out of the build.

## Phase 3 — tray/applet long tail

- [x] Polkit auth agent (added ahead of schedule during Phase 1)
- **Network + Bluetooth**: you're adapting `netpala`/`bluepala` (your own tools) to NixOS yourself — nothing for me to do here, not touching it
- [x] Clipboard manager decided: **cliphist** (see Phase 2 above — moved up since it landed in this pass)
- [x] Rofi menu system ported from `configs/rofi/*.sh` (old repo cloned into scratch, read, cleaned up, not touched again) — all as Nix-defined scripts in `home/rofi.nix`, on PATH as `coel-*`:
  - `coel-main-menu` (`SUPER+SHIFT+Space`), `coel-power-menu` (`SUPER+M`'s sibling, also bound to the physical power key — see below), `coel-actions-menu`, `coel-settings-menu`, `coel-power-profiles-menu`, `coel-emoji-picker` (`SUPER+.`)
  - Screenshot/recording toolchain landed as part of this (`coel-screenshot` bound to `Print`, `coel-screenrecord`) — turned out to have zero Arch-specific dependencies in the original scripts, just Wayland tooling (`grim`/`slurp`/`wayfreeze`/`satty`/`gpu-screen-recorder`), so porting them was small added scope directly in service of `actions.sh` actually working end to end rather than pointing at nothing
  - Fingerprint: `coel-fingerprint-enroll`/`coel-fingerprint-delete` ported (still bare `sudo`, prompts every time — the polkit rule below would remove that friction, still not added)
  - `services.power-profiles-daemon.enable` added — needed for `powerprofilesctl` (used by `coel-power-profiles-menu`), wasn't already on
  - Physical power key: old config blocked logind's default power-key handling via `systemd-inhibit` so it could remap the key to the power menu instead. Added both together now (`exec-once` inhibit in `home/hyprland.nix` + `XF86PowerOff → coel-power-menu`) since the previous blocker (no menu existed yet) is resolved — wiring the bind alone without the inhibit would have risked an immediate poweroff race
  - **Full port pass**: every entry from the original menus is now present — nothing silently dropped. Anything without a real Nix equivalent yet calls `coel-todo "<specific message>"` (a small notify-send wrapper) instead of being omitted:
    - `Install`/`Uninstall` (main menu) — TODO, explains Nix's declarative model doesn't have an imperative installer menu (edit `home.nix`/`configuration.nix` + rebuild instead)
    - `Update` (main menu) — **not** a TODO, this one has a real equivalent: `coel-update` runs the same `sudo nixos-rebuild switch --flake ~/.nixos#coelos` as `~/reload-nix.sh`, in a terminal
    - `WiFi`/`Bluetooth` (settings menu) — TODO, pending your separate netpala/bluepala adaptation
    - `Monitors`/`Keybindings`/`Input`/`Config` (settings menu), and `Hyprland`/`Hyprlock`/`Hypridle`/`Autostart`/`Window Rules` (config submenu, `coel-config-menu`) — all real, several point at the same file now (`home/hyprland.nix` or `home/hypridle.nix`) since those used to be 6+ separate files and ours is unified — not a mistake, a real structural difference
    - `Look & Feel`/`Waybar` (config submenu) — TODO, styling still genuinely not done
    - Fingerprint `Delete` — the original split this into a separate `uninstall.sh` submenu from `settings.sh`'s `Enroll`; since `Uninstall` is now a TODO stub, both live together in a new `coel-fingerprint-menu` (Enroll/Delete) instead, reached from Settings → Fingerprint
    - `clipboard/run.sh` + `clipvault-rofi-img.sh` — **not** ported as scripts, but the feature isn't missing: it's the same thing the existing cliphist `SUPER+V` bind already does (clipvault itself was never adopted, cliphist replaced it back in the initial Phase 2 pass)
  - **Bugs found and fixed while porting**: every menu script had `-p` (rofi's prompt-text flag) immediately followed by another flag with no value — the trailing `-i "Power"`/`-i "Main Menu"` etc. was never actually reaching `-p`. Fixed to `-p "Power"` etc. directly, `-i` kept as rofi's real case-insensitive-matching flag. Also `power-profiles.sh` captured rofi's cancel/exit code (`$?`) *after* the `powerprofilesctl set` call instead of right after the prompt, so the "reopen menu on cancel" logic was checking the wrong command's result — moved back to directly after the prompt. "Audio" opens `pulsemixer` instead of the old script's bare `pulseaudio`, which looked like a leftover/placeholder rather than a real TUI mixer.
  - Still deferred, on purpose, matching your stated priority (working now, themed later): `rofi.rasi` styling, waybar config/styling (including the `screenrecording-indicator` module), Look & Feel
- [ ] KDEConnect tray (kdeconnect-indicator — the daemon itself is already configured in `modules/kdeconnect.nix` and is DE-agnostic)
- [ ] GTK/Qt theming pass (qt5ct/qt6ct — `GTK_THEME = Adwaita:dark` is already set globally in `home.nix`)
- [ ] Fingerprint enrollment polkit rule (`configs/polkit-fprint.rules` — lets `wheel` group enroll fingerprints without the enroll-itself-needs-auth chicken/egg problem; currently missing even though `services.fprintd.enable` is on)
- [ ] Lid-close behavior (`configs/power/logind-power.conf`): old config suspends on lid close even on AC power. Not ported — power-key handling is now covered (see above), this is just the lid switch, independent and still open
- [ ] Minor UX polish not ported: old media-key binds ran a `dismiss-track-control-notifs.sh` script before calling swayosd, to stop a lingering "track changed" notification bubble from overlapping the OSD popup. Skipped for now (cosmetic, not functional) — ours call `swayosd-client`/`playerctl` directly

## Architecture note: keeping Hyprland tools from leaking into Plasma

`home/hyprland.nix` sets `wayland.systemd.target = "hyprland-session.target"`. This matters because home-manager's Wayland service modules (`services.hypridle`, `services.awww`, `services.swayosd`, `services.cliphist`, and any future ones) default their systemd `WantedBy` to `wayland.systemd.target`, which **defaults to the generic `graphical-session.target`** — a target Plasma's session also activates. Without this override, all of those services would start under Plasma too. Verified by building the actual generated units: all four currently point at `hyprland-session.target` specifically, confirmed via a full local build. **Any new Hyprland-session service added later must use a home-manager module that respects this option (or be wired through `exec-once`, which is inherently Hyprland-only) — don't hand-roll a `systemd.user.services.*` block that skips it.**

## Explicitly deferred — styling/theming (per your priority: working now, themed later)

- hyprlock visual config, waybar.jsonc + rofi.rasi styling, custom SDDM theme (`theme/sddm/`), GTK theme package "CoelOS", `oreo_spark_light_pink_cursors` cursor theme, emoji picker, custom rofi power/main menus, wallpaper image + cycling

## Skip entirely — Arch/Omarchy-specific, doesn't apply to NixOS

- `bin/pacman-install.sh`, `bin/yay-install.sh`, `bin/pac-yay-uninstall.sh`, `bin/tui-install.sh`, `bin/tui-uninstall.sh`, `bin/webapp-*.sh`, `install.sh`, `fix-bootmgr.sh` — imperative package-manager scripts, superseded by Nix's declarative model
- `configs/limine.conf` — different bootloader (you're on `systemd-boot`)
- `move-hyprland-run` window rule — targets Omarchy's `hyprland-run` launcher, which you've replaced with rofi

## Notes on the old config (corrected/resolved)

- ~~`awww-daemon` typo~~ — not a typo, `swww` was renamed to `awww` upstream and nixpkgs already reflects the rename (`pkgs.swww` is now just an alias that warns and points to `pkgs.awww`). Using `pkgs.awww` directly.
- `input.conf` has a live (uncommented) `device { name = epic-mouse-v1; sensitivity = -0.5; }` block — `epic-mouse-v1` is Hyprland's own placeholder example device name from the default generated config, not a real device. Dead/no-op, not carried forward.
- Keybinds now match the old config: `SUPER+W` killactive, `SUPER+M` exit, `SUPER+SHIFT+F` fullscreen added, `SUPER+L` locks.

## Phase 4 — cutover decision

- [ ] Once Hyprland is the actual daily driver: decide whether to keep Plasma installed permanently as a fallback, or remove `services.desktopManager.plasma6` and its package excludes

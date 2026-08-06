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
- [ ] Notifications daemon: **mako** (confirmed — `theme/mako` exists in old dotfiles; mako is D-Bus-activatable so it likely doesn't even need an `exec-once`)
- [ ] hyprlock + hypridle — old timings to reuse: lock at 5min, DPMS off at 10min, suspend at 20min (`hypridle.conf`); `SUPER+L` locks
- [ ] Wallpaper: **swww** + a cycling script (old `bin/swww-cycle.sh`, rotates every 30min) — not hyprpaper/swaybg
- [ ] Volume/brightness OSD: **swayosd** (`swayosd-server` + `swayosd-client`), bound to the `XF86Audio*`/`XF86MonBrightness*` keys — moved here from Phase 3, it's daily-driver-essential not a tray afterthought
- [ ] Mouse-drag window move/resize: `bindm = SUPER, mouse:272, movewindow` / `mouse:273, resizewindow` — missing entirely right now, pure ergonomics, not styling
- [ ] Window resize keybinds: `SUPER+SHIFT+arrows` → `resizeactive` — also missing
- [ ] Window rules: `suppress-maximize-events` (ignore apps' own maximize requests) and `fix-xwayland-drags` (known XWayland drag bug workaround) — functional, not cosmetic
- [ ] Portals: resolve the `xdg-desktop-portal` backend-priority warning that's been showing since Phase 1 (`xdg.portal.config`), needed for screen sharing in browser/Discord/OBS to work correctly

## Phase 3 — tray/applet long tail
- [x] Polkit auth agent (added ahead of schedule during Phase 1)
- [ ] **Network + Bluetooth: open decision.** Old setup used self-built TUI apps (`netpala`/`bluepala`, your own tools, class `com.joelsgc.netpala`/`bluepala`) in floating windows instead of tray icons — not in nixpkgs, would need packaging from source. Alternative: plain `nm-applet` + `blueman` tray icons. Need your call here.
- [ ] Clipboard manager: **open decision.** Old setup used `clipvault` (`wl-paste --watch clipvault store`) + a custom rofi picker script, not `cliphist`. Is clipvault your own tool too, or a third-party one? Determines whether it needs packaging.
- [ ] KDEConnect tray (kdeconnect-indicator — the daemon itself is already configured in `modules/kdeconnect.nix` and is DE-agnostic)
- [ ] GTK/Qt theming pass (qt5ct/qt6ct — `GTK_THEME = Adwaita:dark` is already set globally in `home.nix`)
- [ ] Fingerprint enrollment polkit rule (`configs/polkit-fprint.rules` — lets `wheel` group enroll fingerprints without the enroll-itself-needs-auth chicken/egg problem; currently missing even though `services.fprintd.enable` is on)
- [ ] Lid-close/power-key behavior (`configs/power/logind-power.conf`): old config suspends on lid close even on AC power, and disables the hardware power key's default action so it can be remapped to a custom rofi power menu instead — hold the power-key remap until that menu exists (Phase 3/4), but lid-suspend-on-AC could be ported independently if wanted
- [ ] Screenshot/recording toolchain (later, not urgent): `grim` + `slurp` + `wayfreeze` + `satty` for screenshots, `gpu-screen-recorder` for recording — full working scripts already exist in old `bin/`

## Explicitly deferred — styling/theming (per your priority: working now, themed later)
- hyprlock visual config, waybar.jsonc + rofi.rasi styling, custom SDDM theme (`theme/sddm/`), GTK theme package "CoelOS", `oreo_spark_light_pink_cursors` cursor theme, emoji picker, custom rofi power/main menus

## Skip entirely — Arch/Omarchy-specific, doesn't apply to NixOS
- `bin/pacman-install.sh`, `bin/yay-install.sh`, `bin/pac-yay-uninstall.sh`, `bin/tui-install.sh`, `bin/tui-uninstall.sh`, `bin/webapp-*.sh`, `install.sh`, `fix-bootmgr.sh` — imperative package-manager scripts, superseded by Nix's declarative model
- `configs/limine.conf` — different bootloader (you're on `systemd-boot`)
- `move-hyprland-run` window rule — targets Omarchy's `hyprland-run` launcher, which you've replaced with rofi

## Flagged — looks like a bug in the old config
- `autostart.conf` has `exec-once = awww-daemon && ...` — almost certainly a typo for `swww-daemon` (the script it chains to is literally `swww-cycle.sh`, and `awww-daemon` isn't a real binary). Won't carry the typo forward.
- `input.conf` has a live (uncommented) `device { name = epic-mouse-v1; sensitivity = -0.5; }` block — `epic-mouse-v1` is Hyprland's own placeholder example device name from the default generated config, not a real device. Dead/no-op, safe to drop.
- Old `killactive` was bound to `SUPER+W`, ours is `SUPER+Q`; old "exit Hyprland" was `SUPER+M` alone, ours is `SUPER+SHIFT+M`. Minor muscle-memory mismatches — flagging in case you want them to match exactly.

## Phase 4 — cutover decision
- [ ] Once Hyprland is the actual daily driver: decide whether to keep Plasma installed permanently as a fallback, or remove `services.desktopManager.plasma6` and its package excludes

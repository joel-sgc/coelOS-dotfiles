# TODO

## Session hub / login (from the "what's missing" review)

- [ ] Guest can reach Tailscale: block `tailscale0` for the guest uid (modules/guest.nix, nftables table `coel-guest`).
- [ ] Guest `/dev/shm` is not wiped at logout.
- [ ] Power buttons on the login screen (suspend / reboot / power off) do not warn that other sessions are still running.
- [ ] No way to end someone's session from the login screen (a hung session needs a console).
- [ ] Login screen can only dim, never turn the panel off (amdgpu ignores backlight off); real off only happens at suspend. Decide whether that is acceptable.
- [ ] Try on real hardware: "staying awake" notice, second monitor on the login/lock screen, wake from suspend through the hub, repeated guest login/logout.
- [ ] Tests: nothing covers the login screen's display names or guest-last ordering; the VM test uses fake sessions, not a real Hyprland or fingerprint reader.
- [ ] home/quickshell/STATUS.md is a very long changelog; add a short "how the hub works" overview.

## Hyprland in Lua + workspace grid

Decision: no Niri, no scrolling strip. Hyprland's whole config is now Lua
(home/hyprland/hyprland.lua, deployed by home/hyprland.nix with `configType =
"lua"`). Workspaces are a grid in rows of 100, unbounded sideways; each row
remembers the column you left it on. The grid logic lives in the Lua file
(row/column helpers, a `workspace.active` listener, per-move slide animation).

- [x] Full migration to Lua; legacy `hyprctl dispatch/keyword` callers converted (hypridle dpms, panel workspace chips, notifications focus, launcher toggles, displays modal, cursor warp). Tested in a nested Hyprland.
- [x] Grid logic split into home/hyprland/grid.lua (no Hyprland calls) with unit tests in home/hyprland/grid_test.lua: `lua home/hyprland/grid_test.lua` (Lua 5.5) or `nix build .#checks.x86_64-linux.hyprland-grid`. Includes a fuzz test; deliberately breaking the logic is caught. Run it after any change to the grid.
- [ ] Verify on the real touchpad that `workspace_swipe_use_r` fixed the sideways swipe hopping rows (the likely cause), and that one up/down swipe = one row.
- [ ] Try on the real machine: the up/down swipe (a Lua function gesture; it may need its direction swapped), the sideways built-in swipe, hypridle dim/wake, the displays modal, the launcher's eye-candy and monochrome toggles, clicking panel workspace chips.
- [ ] Any new code that talks to Hyprland must use Lua syntax: `hyprctl dispatch 'hl.dsp...'`, `hyprctl eval '...'` (the old `dispatch workspace N` and `keyword` forms no longer work). `-j` queries are unchanged.
- [ ] Overview (four-finger swipe up: zoomed-out view of the workspace grid; click to jump, drag windows between workspaces). Plan: build it in Quickshell (Hyprland IPC for layout, ScreencopyView for live previews) rather than a plugin; `hyprspace` is the plugin fallback to test.
- [ ] Tune after living with it: whether Super+1..0 should stay in the current row or always mean row 0, whether Page Up/Down should be bound at all.

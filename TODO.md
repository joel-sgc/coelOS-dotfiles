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
"lua"`). Workspaces are a grid of five rows (maximum) of 100 columns, with the sideways
swipe stepping along a row; each row
remembers the column you left it on. The grid logic lives in the Lua file
(row/column helpers, a `workspace.active` listener, per-move slide animation).

- [x] Full migration to Lua; legacy `hyprctl dispatch/keyword` callers converted (hypridle dpms, panel workspace chips, notifications focus, launcher toggles, displays modal, cursor warp). Tested in a nested Hyprland.
- [x] Grid logic split into home/hyprland/grid.lua (no Hyprland calls) with unit tests in home/hyprland/grid_test.lua: `lua home/hyprland/grid_test.lua` (Lua 5.5) or `nix build .#checks.x86_64-linux.hyprland-grid`. Includes a fuzz test; deliberately breaking the logic is caught. Run it after any change to the grid.
- [ ] Try the three-finger swipes on the real touchpad: sideways is Hyprland's own finger-following swipe in its default mode (steps only between workspaces that exist, so it cannot go below workspace 1, but it can reach another row's workspace if you swipe past the end of a row); up/down are one row per swipe. Check that holding halfway shows the in-between state and that left on workspace 1 does nothing. Animation speed for the up/down slide is `SLIDE_SPEED` in home/hyprland/hyprland.lua.
- [x] Do NOT enable `workspace_swipe_use_r`: it lets the built-in swipe target workspace 0 / a huge id, and Hyprland crashed (SEGV in CUnifiedWorkspaceSwipeGesture::end(), 18:40 Nov 15; report in ~/.cache/hyprland). A discrete Lua swipe was tried as a replacement but loses the finger-following feel, so the built-in swipe is back in its default mode. Never move workspaces from inside the workspace.active event (an earlier guard did).
- [ ] Try on the real machine: the up/down swipe (a Lua function gesture; it may need its direction swapped), the sideways built-in swipe, hypridle dim/wake, the displays modal, the launcher's eye-candy and monochrome toggles, clicking panel workspace chips.
- [ ] Any new code that talks to Hyprland must use Lua syntax: `hyprctl dispatch 'hl.dsp...'`, `hyprctl eval '...'` (the old `dispatch workspace N` and `keyword` forms no longer work). `-j` queries are unchanged.
- [x] Workspace overview, Niri/Mission-Control style: a four-finger swipe up freezes your screen and shrinks it into a stack of five miniature desktops (one per row, each as you left it, its other workspaces beside it; wallpaper dimmed behind). Up/Down or the mouse moves the selector; Enter or a click takes you to that row on its remembered column, growing that desktop back to full size; Escape or a background click puts your desktop back. In the panel (home/quickshell/Overview.qml + overview/), built only while open, window pictures taken once. Tests: `nix build .#checks.x86_64-linux.overview-layout` (20) and `...hyprland-grid` (54). Not yet seen on the real machine: the live screen picture and window pictures, the animation's smoothness, and the four-finger gestures.
- [ ] Overview follow-ups only if wanted: a keybind (e.g. Super+Tab), closing a window from it, tuning the animation speed (260 ms) and dimming.
- [ ] Tune after living with it: whether Super+1..0 should stay in the current row or always mean row 0, whether Page Up/Down should be bound at all.

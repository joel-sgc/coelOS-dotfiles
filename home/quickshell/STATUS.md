# CoelOS Quickshell shell: working notes

Quickshell (Wayland/Hyprland) bar, launcher, notifications, lock/login, power menu,
widgets, polkit agent and share picker, replacing waybar, rofi, mako, hyprlock, SDDM.
Everything here is built and real-hardware tested unless marked otherwise. This file is
for non-obvious facts only; for what code does, read the code. History is in `git log`.

## Design source and workflow

- Visual/behavioral source of truth is the mockups in `~/.nixos/example/*.dc.html`
  (`Quickshell Bar`, `Desktop Widgets v2`, `Display Modes`, `Workspace Overview`). Read the
  relevant one before guessing. The user edits these themselves: don't overwrite them.
  (`support.js` there is mock-page plumbing, not logic to port; the converter logic was
  in the `.dc.html`'s inline script.)
- Pattern: hardcoded UI first (screenshot-approved), real logic in a second pass.
- The user runs a **live production** Quickshell that hot-reloads QML. Validate with
  `quickshell ipc -p ~/.nixos/home/quickshell show` and by tailing
  `/run/user/1000/quickshell/by-id/*/log.qslog` for WARN/error after an edit. **Never
  pkill/relaunch it without asking.** Bare `qmllint` is mostly import-noise; trust the log.
- Nix-level changes: `nix build .#nixosConfigurations.coelos.config.system.build.toplevel
--no-link` verifies without switching. The user switches and commits themselves; stage
  with `git add -- <files>` only if asked. Flakes only see git-tracked files, so `git add`
  new files before a rebuild.
- Popup content gated on a `popupOpen`-style prop only runs while open; to test, have the
  user open it or force the gate with a `// TEMP` comment and revert.
- Icons come from `sysPanel/Phosphor.js` (codepoint table). Verify codepoints against
  Phosphor's upstream `style.css`, never invent them. (Nerd-font rules: see `AGENTS.md`.)

## Layout

```
shell.qml             root; instantiates Panel, Border, Launcher, Notifications, Widgets, Polkit, Osd, Overview
sysPanel/             bar (Panel.qml), Popup.qml dropdown chrome, dropdowns/, buttons/, components/,
                      Calc.js, Convert.js, Phosphor.js
launcher/             LauncherPanel.qml + backends/ (one Item per data source)
notifications/        NotificationsBackend.qml (the org.freedesktop.Notifications server)
widgets/, polkit/, screenshare/, powermenu/, lock/, greeter/, overview/, displays/
*-shell.qml           standalone entry points (lock-real, power-menu, screenshare, greeter, display-modes)
```

Quickshell sandboxes each config to its root dir, so standalone entry points must sit at
the config root, not inside their feature folder.

## QML gotchas (each bit us live)

- `.qmltypes` `Method` entries aren't proof of invokability: `SystemTrayItem`/`QsMenuEntry.
sendTriggered()` and `WlSessionLock.unlock()` threw or hung. Use `entry.triggered()` and
  `sessionLock.locked = false`. Trust a live TypeError over metadata.
- Never anchor a Row/Column child along the positioner's managed axis; use a plain `Item`
  with explicit x/y. `Layout.*` is ignored unless the parent is a real Layout.
- A child property named like the parent's `id` self-shadows (use `nRoot`, not `dropdownRoot`).
- `Item` owns `left/right/top/bottom/horizontalCenter/...`: don't name your own properties
  those ("Cannot override FINAL property").
- Two `Component.onCompleted` on one object = "Property value set multiple times".
- `Component.onCompleted: forceActiveFocus()` on a static child fires for every instance at
  creation, silently eating keystrokes. Use an `on<State>Changed` handler.
- `font.pixelSize`/`maximumLineCount` are ints and reject fractions/`undefined` silently
  (`0` = unlimited). `&&` can yield `undefined` for a `bool` property: use `!!`.
- `Grid { columns: 2 }` counts delegates, not children inside one.
- An unbounded `Column`+`Repeater` overflows its container; use a `ListView` with `clip`.
- `Greetd.launch()` silently drops long command arguments (see Greeter).
- `FloatingWindow` wants `implicitWidth/Height`; `PanelWindow` (layer-shell) doesn't work
  under `cage`.
- `Pal.qml` in widgets/ is not called `Palette` (clashes with a QtQuick type); its `qmldir` is required.

## Bar and dropdowns

Network, Audio, Bluetooth, Power, System, Calendar(+todo, SQLite via `QtQuick.LocalStorage`),
Tray, Notifications. Dropdown `rightMargin`s are hand-tuned guesses. The opaque border
(`bgColor` as `borderColor` in `shell.qml`) is intentional; don't revisit.

**Tray right-click**: `TrayDropdown.qml` resolves the DBusMenu with `QsMenuOpener` into a
themed `Popup.qml` dropdown (one shared instance, one submenu level). `QsMenuAnchor`
(native menu) was abandoned: needs `//@ pragma UseQApplication` + restart and looks wrong.
Width is 340 (Panel's `contentWidth` includes 32px side padding). Click-through of a real
menu action (e.g. Steam "Exit") is still unconfirmed.

## Launcher

Replaced rofi (`rofi.nix`, its scripts, netpala/bluepala all deleted). Bound via Hyprland to
`quickshell ipc -p ~/.nixos/home/quickshell call launcher toggle|openClipboard|openEmoji`.

- Categories (search-priority order): launch, ssh, actions, convert, math, system, clipboard;
  emoji is search-only (browsable via `super+.`). Overall match priority: apps, other
  categories, clipboard, emoji (clipboard once outranked real matches).
- `ssh`: `scripts/list-ssh-hosts.py` over `~/.ssh/config`; `SshBackend.blacklist` is
  user-edited, don't assume it's empty.
- `actions`: toggles (DND, keep-awake, mic mute, monochrome shader, eye candy) + capture. Items
  with `groupLabel` get header toppers even when just browsing. **Night light and charge
  limit were removed on purpose** (the Framework EC charge-limit override doesn't survive
  reboot); a `framework-laptop-kmod` integration was built and reverted. Don't re-add unasked.
- `convert`: `Convert.js` `evaluate(raw, liveRates, ratesUpdated)`; live rates from
  `open.er-api.com/v6/latest/USD` hourly (chosen because ECB sources lack Latin American
  currencies), hardcoded table is only a fallback. A valid conversion beats the calculator.
- Search bangs `@g`/`@ddg`/`@yt` open directly in Zen.
- "About this system" runs fastfetch in the floating `com.joelsgc.info` terminal; "Purge" runs `coel-purge`.
- Lock entries call `quickshell -p .../lock-real-shell.qml` (never hyprlock directly).

## Notifications

Quickshell's own `NotificationServer` is the `org.freedesktop.Notifications` server; mako is
gone (they can't coexist). History in SQLite (`CoelOSNotifications`, 200-row retention),
per-app mute and DND persisted; the launcher DND toggle uses the backend directly.

- Toasts are positioned to match tiled windows: `Panel` exclusive zone 36 + `gaps_out` +
  `border_size`, radius = `decoration.rounding`. Re-measure with `hyprctl -j clients/monitors` if gaps change.
- The `image`/`image-path` hint is usually just the sender's icon, not a photo; Satty's real
  screenshot path is regexed from its body (`File saved to '<path>'`).
- "Show app" is a best-effort `hyprctl -j clients` match; per-app icon decoding is a
  placeholder; Phosphor only ships Regular weight (no fill bell).
- Untested against a real reply-capable sender (inline reply / actions), and the history
  prune past a handful of rows.

## Lock screen and greeter

**Lock** (`lock/`, entry `lock-real-shell.qml`): `WlSessionLock`; auth via `PamContext` (not
pamtester) against two parallel single-purpose PAM services in `configuration.nix`:
`quickshell-lock` (password only) and `quickshell-lock-fp` (fingerprint only, self-restarting).
A shared stack makes the password wait behind the fingerprint conversation. The fingerprint
icon is a passive indicator from `fprintd-list`.

**Greeter** (`greeter/`, `modules/greeter.nix`, `services.qs-greeter.enable`): greetd -> `cage`
-> quickshell, reusing the lock UI in `mode: "login"`. `users.json`/`sessions.json` are
generated at build time. Mock mode when `Greetd.available` is false (`greeter-shell.qml`).
Hard-won fixes, all still necessary:

1. Plain `FloatingWindow` with `implicitWidth/Height` (cage has no layer-shell).
2. `cage -- bash -c "sleep 1; exec quickshell ..."`: output-enumeration race otherwise gives
   "There are no outputs" / `EGL_BAD_SURFACE`. (`LIBSEAT_BACKEND=logind` was not the fix.)
3. `greetd.service` `Type = mkForce "simple"` (default `idle` adds ~6s boot delay).
4. cage debug and the launched session's output are redirected to `/tmp/qs-greeter-*.log`
   to avoid a console text flash.
5. **`Greetd.launch()` silently drops long commands** (you get a bare `/bin/sh`). Every
   session writes its command to `/tmp/qs-greeter-launch.sh` and launches
   `["/bin/sh","/tmp/qs-greeter-launch.sh"]`. Read this before touching `doLaunch()`.
6. Last-used session is persisted to `/var/lib/qs-greeter/last-session`, written by the
   greeter user in the same step as the launch script (not from inside it: that runs as the
   target user and hit "Permission denied"). Default is "hyprland" by explicit id lookup
   (`hyprland-uwsm` sorts first).
7. greetd PAM order is password -> keyring -> fingerprint (`authinfo_unavail=ignore`).
   Fingerprint-first made a good scan skip `pam_gnome_keyring`, so the keyring never
   unlocked. The `default` keyring alias now points at `login`; items in the old
   "Default keyring" (e.g. the VPN password) need re-storing (`coel-vpn-set-password`).
   Recovery if login breaks: TTY (`login` PAM untouched), or the previous generation.
8. `WLR_NO_HARDWARE_CURSORS=1` for cage (ghost cursor after handoff).
9. UWSM: `programs.hyprland.withUWSM = true`, hand-rolled `hyprland-session.target`,
   `uwsm/env-hyprland`, and `wayland.windowManager.hyprland.systemd.enable = false` in
   `home/hyprland.nix`.
   Open: fprintd's ~30s timeout delays a password-only login if the sensor is untouched;
   greeter avatars would need per-user images baked into the store.

## Session hub, guest, idle (`modules/session-hub.nix`, `modules/guest.nix`)

`scripts/coel-hub.py` and `scripts/coel-vt-guard.py`; VM test `modules/session-hub-test.nix`
(`tests/nixos/`). The login screen (greeter) lives on VT1 permanently and never starts a
session; sessions run on idle greetd "host" instances on VT7/VT8 (VT2-6 stay plain consoles).

- Login: greeter runs `coel-hub auth USER --host auto --cmd ...` (PAM against a host's greetd
  socket). After `start_session` the hub kills the host's placeholder greeter, otherwise greetd
  waits ~5s for it to exit.
- Lock (`coel-hub lock`): start the in-session lock, wait for the compositor-confirmed marker
  (`Lock.qml` on `WlSessionLock.secure`), then switch to VT1, only if that session is the one
  on screen. Resume: password check on the main greetd, then `coel-hub resume` writes
  `/run/coel-hub/unlock/<session>`; the lock accepts only a file newer than its own lock
  (writable only by the greeter user, so it can't be forged; logind's unlock-session would let
  the session's own user unlock).
- `coel-vt-guard` (root): VT 7/8 may be on screen only while a hub-approved session owns it;
  otherwise it bounces to the login screen (0.8s grace for logout). It never waits on
  VT_WAITACTIVE (can hang forever).
- Hosts start **one at a time**, chained with `After=`, each finishing when its idle greeter is
  up (`coel-hub wait-host`): greetd blocks until its VT is on screen, so parallel hosts raced
  and hung boot ~2 runs in 5.
- One session per account (enforced in `coel-hub auth`): a signed-in account resumes its
  session; a second is refused (avoids shared bus/profile-lock conflicts).
- Autolock timeline: 10 min idle -> `coel-hub lock` (hypridle); login screen backlight to 0
  after `hubBlankAfter` (300 s), suspend after `hubSuspendAfter` (600 s); 0 disables. The guard
  does this since cage can't blank or idle. Brightness is saved under `/run/coel-vt-guard` and
  restored on input, leaving VT1, resume, daemon stop/crash (a dead daemon must never leave
  the laptop dark). amdgpu rescales 0 to the panel minimum, so suspend is what really turns
  it off. The session's own suspend is `coel-hub suspend-fallback` (only if it is on screen).
  The login screen shows "staying awake" when `coel-hub holds` finds logind block inhibitors.
  Input events are only counted, never read or logged. Real backlight/suspend-resume are
  untestable in the VM.
- Guest (`modules/guest.nix`, `home/guest.nix`): tmpfs home (4G), wiped by `coel-guest-reset`
  after the last session ends; passwordless via greetd only (console `login` refuses empty
  passwords); no sudo, Nix builds, VPN (nftables) or NetworkManager polkit actions; same
  Hyprland/Quickshell minus personal modules.
- Limits/recovery: Ctrl+Alt+F2 is a plain console; or boot the previous generation; or remove
  `services.coel-hub.enable`. After first enabling, log out/in so the new greeter takes over.
- Quickshell QML cache is on for logins and wiped on every rebuild (`clearQuickshellQmlCache`).

## Power menu

`powermenu/PowerMenu.qml` + `power-menu-shell.qml`, launched by `coel-power-menu`
(`home/os-commands.nix`, bound to `XF86PowerOff`) as a **separate** Quickshell process (pgrep
guard against stacking), pointed at the live repo path so edits hot-reload. Layer Overlay +
Exclusive keyboard focus. Lock/suspend run immediately; log out/reboot/shut down arm a 5s
countdown. Log out is `hyprctl dispatch exit`.

## Widgets, polkit, share picker

- **Widgets** (`Widgets.qml`, `widgets/`): weather (Open-Meteo, IP location), calendar, kanban as
  Bottom-layer cards. Data in `~/.local/share/coel/` (`COEL_DATA_DIR` overrides). Needs the
  Phosphor-Fill font (`home/quickshell-phosphor-font.nix`). Keyboard needs a click first.
  IPC: `... call widgets toggle|newcard`. Test headlessly with sway + a virtual-pointer client.
- **Polkit** (`Polkit.qml`, `polkit/`): `Quickshell.Services.Polkit`. Only one agent per session
  (the KDE one was retired). API gives no caller app/pid. fprintd arrives as PAM text; PAM asks
  for the password only after the ~30s sensor timeout. Test with `pkcheck -a
org.freedesktop.systemd1.manage-units --process $$ --allow-user-interaction` in headless sway
  (`pkexec` fails: no_new_privs). A successful auth is NOT verified.
- **Share picker** (`screenshare-shell.qml`, `screenshare/`, built into `coel-share-picker`
  with an `xdph.conf` in `home/os-commands.nix`): the portal contract (xdph 1.3.12): stdout
  `[SELECTION]<r?>/screen:NAME|window:ID|region:NAME@x,y,w,h` **with a trailing newline**
  (without it the portal hangs); window IDs must come from `XDPH_WINDOW_SHARING_LIST` (others
  hang it); empty output = cancel; `--allow-token` only if `allow_token_by_default`. Quickshell
  can't print stdout cleanly, hence a temp-file handoff. Multi-select, cursor checkbox and the
  requesting-app line are dropped (portal can't carry them). Test by calling the ScreenCast
  portal over D-Bus yourself (`dbus-next`; don't introspect the portal object).

## GlobalProtect VPN

Moved to openconnect; see `modules/globalprotect/globalprotect-vpn-automation.md`. The panel's
VPN modal drives `coel-vpn-*`.

## Open items

- fprintd timeout on the login screen; greeter avatars.
- Notification reply/action path and history prune untested with real senders.
- Sharing indicator for the share picker (separate feature, not built).

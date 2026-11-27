# CoelOS Quickshell shell: working notes

Quickshell (Wayland/Hyprland) bar, launcher, notifications, lock/login, power menu,
widgets, polkit agent and share picker, replacing waybar, rofi, mako, hyprlock, SDDM.
Everything here is built and real-hardware tested unless marked otherwise. This file is
for non-obvious facts only; for what code does, read the code. History is in `git log`.

## Design source and workflow

- Visual/behavioral source of truth is the mockups in `~/.nixos/example/*.dc.html`
  (`Quickshell Bar`, `Desktop Board`, `Pill Board`, `Display Modes`, `Workspace Overview`). Read the
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

- A property and a function with the same name: the property silently wins and calls fail
  with "is not a function" (DeskState had `open` as both; the shelf's [+] broke).
- `sed -i` (or anything that replaces a file instead of writing it in place) silently stops
  hot reload of that file: the watcher stays on the old inode. Edit in place; to recover, make a
  real change to shell.qml (an unchanged rewrite doesn't reload).
- `.qmltypes` `Method` entries aren't proof of invokability: `SystemTrayItem`/`QsMenuEntry.
sendTriggered()` and `WlSessionLock.unlock()` threw or hung. Use `entry.triggered()` and
  `sessionLock.locked = false`. Trust a live TypeError over metadata.
- Never anchor a Row/Column child along the positioner's managed axis; use a plain `Item`
  with explicit x/y. `Layout.*` is ignored unless the parent is a real Layout.
- A child property named like the parent's `id` self-shadows (use `nRoot`, not `dropdownRoot`).
- `Item` owns `left/right/top/bottom/horizontalCenter/...`: don't name your own properties
  those ("Cannot override FINAL property").
- A property named `on` + Capital (`onToday`, `onColor`) reads back as undefined from
  outside: QML takes it for a signal handler. Also FINAL: `x`, `y` on any Item delegate, and
  property names can't start with an uppercase letter.
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

## Live-activity island (`island/`)

Design: `example/Pill Board.dc.html` (rules, tiers, motion) and `Pill Prototype.dc.html`.
`IslandEngine` (one, in `Panel.qml`) owns chips/glances/interrupts/card; `IslandView` per
bar is one Overlay surface (namespace `coel-island`, no_anim layer rule) that draws the
island both docked and floating, so lift/land is one morph. Sources live in
`island/sources/` and only expose a `chips` list plus `engine.glance/interrupt/withdraw`
calls; parts are plain objects (`Parts.js`). The clock is anchored at the exact centre on
purpose (the island docks against its left edge).

- `PrinterSource` runs `scripts/coel-bambu.py` (stdlib-only MQTT + camera client, JSON lines
  over stdio). P1S in LAN-only + Developer Mode (needed for pause/resume/stop); credentials
  from `coel-bambu-setup` (keyring, `scripts/coel-bambu-setup.sh`). Camera is the P1 JPEG
  stream on :6000, not RTSP. The printer is **only reachable over Tailscale**: idle = one
  check-in every 5 min, then hang up; printing = stay connected; lost mid-print = greyed
  chip with "seen hh:mm", retries with backoff, dropped once it would have finished.
  A dropped Tailscale route goes silent (no FIN), hence the no-traffic timeout.
- The first daemon report after a (re)start only syncs (`primed`): reloads must not replay
  "Print finished" / "Print failed". FAILED with print_error 0x0300400C is a user cancel.
- UI testing without the printer: `quickshell ipc ... call island demo print|pause|fault|fail|done|live`,
  plus `card`, `dismiss`. A fake P1S (TLS MQTT broker + camera) was used to test the daemon;
  it isn't kept in the repo.
- `IslandView`'s surface stays 720 px tall while mapped: resizing a mapped layer surface
  flashed a tall frame.
- `DemoSource` (music/cal/rec chips) is mock-only; delete when real sources exist.
- `AssistantSource` keeps the `assistant` IPC that `coel-ask-screen.sh` calls. The board's
  card / follow-up / history / discreet mode are not built.
- Not built yet: interrupt sounds (step 6 sound pack), glances filing into the bell.

## Modes and the desktop (`modes/Modes.qml`, `desktop/`)

Design: `example/Desktop Board.dc.html` (+ Prototype). Modes is a singleton; inference lives
in Quickshell on purpose (every input is already here). Priority gaming > class > deep_work >
printing > music > evening > morning ("default" after 12:00).

- Class = timed event from a gcal-url feed labelled `class`, 0 min lead (the unlabelled
  feed is LMS deadlines, which look identical: 30 min, course-code titles). Gaming = focused
  fullscreen window, Hyprland `contentType` "game" or a class regex, debounced 2 s in / 30 s
  out. Deep work = Pomodoro running (its waiting break counts 20 min) or a "focus"/"deep work"
  calendar block. Printing comes from `PrinterSource` bindings; a finished/failed print counts
  30 min only if we saw it end (`printerEndedAt`): the P1S reports an old FAILED forever.
- Config: `settings.toml [modes.*]` via `scripts/settings-table.py` (both TOML parsers must
  accept it: `python3 tests/run.py hyprland-settings`). A mode's `dnd` feeds
  `NotificationsBackend.quiet`, never the user's own `dnd`.
- Override (desktop chip `M` menu, launcher, `ipc call modes set <m>|auto|menu`) holds until
  the next change, 1 hour, or forever; the last two persist in `modes.json`.
- The mode is shown on the desktop and in the launcher, **not in the pill** (board rule).
- Desktop: one Bottom-layer, full-screen `DesktopScreen` per screen (cards glide between
  hero / rail / shelf inside one surface; the input mask is per card). `Layout.js` is the
  board's RECIPE + pins/minimize, pure. Card data lives in `desktop/data/` singletons, so
  every size and monitor share one copy (Pomodoro no longer needs a "primary" instance).
  Pins/minimizes persist in `widgets.json`. Cards: `desktop/cards/`, each handles every
  size it has (L/F/R/C/S/M) plus its keys; the slot adds m (minimize), p (pin), M (menu).
- Cards align to window edges: bar + `gaps_out` (re-read on config reload), 20 px between
  cards; the shelf takes every card the recipe leaves out (not just the board's list) and wraps
  upward. Gaming keeps the board's empty shelf.
- Shared services (`services/`, singletons): `Printer` (owns coel-bambu.py; the pill's
  PrinterSource only maps it to chips), `Music` (Mpris, skips the playerctld proxy), `Phone`
  (KDE Connect polled via `scripts/phone-state.py` + busctl; "send file" uses `coel-pick-file`,
  a dbus-next portal FileChooser client: a one-shot `gdbus call` can't wait for the portal's
  Response). `desktop/data/NextData` treats the unlabelled gcal feed as LMS **deadlines** (due
  rows only, never a countdown) and is evening-aware before 04:00.
- A FINISHED/FAILED the P1S still reports from an old print reads as idle (`Printer.oldEnd`).
- Quickshell keeps layer surfaces across reloads, so changing `WlrLayershell.layer` needs a
  restart; to screenshot the desktop, switch to an empty workspace
  (`hyprctl dispatch "hl.dsp.focus({ workspace = 4, on_current_monitor = true })"`) and back.
- Pill hand-off: each DesktopScreen publishes its open (hero/rail) card rects to
  `DeskState.openRects[screen]`; on an empty workspace the screen's IslandView drops chips whose
  `deskCard` is open (`engine.specWithout`) and flies ghost chips between dock and card
  (280 ms, 40 ms stagger, card flashes on landing). Glances with a `cardId` whose card is on
  the focused empty desktop are skipped (`engine.handedCards`) and flash the card instead.
  The island surface is full screen height so ghosts can reach any card.
- Selected day (`CalendarData.selOffset`) is shared by the calendar and next-up cards (h/l,
  [ ], t, click a day; `ipc call widgets day <n>|today`); it snaps back to today after 5 min.
- Greeting (`desktop/Greeting.qml`): first unlock of the day (day starts 04:00) or after 4+ h
  away (`greeting.json` lastDay/lastSeen; lastSeen is set on lock and by a 5-min heartbeat, so
  suspend counts as away). `lock/Lock.qml` calls `ipc call greeting locked|unlocked`; a real
  shell start (login) counts too, a hot reload doesn't (`PersistentProperties`).
  Empty workspace: full-screen overlay timeline driving `DeskState.greetPhase` (cards hidden,
  staggered in, shelf + chip last; ~3 s hold, `holdMs`); windows open: `DeskState.greetGlance` -> one pill glance,
  full version on the next empty desktop before 12:00. `ipc call greeting test <variant>|glance`.
- Not built yet: second monitor rail (phase 4, deferred by the user), kanban drag-and-drop, the phone's island chips
  (calls, notifications), "print again".

## Seamless boot and login

One picture ties it together: the COELOS wordmark (730x160, same artwork as
`assets/coelos-wordmark.png`) centred on flat #282c34, which is Plymouth's last frame.
- Greeter intro (greeter/Greeter.qml): first frame is that picture, then the wordmark glides
  into the auth card. Outro: on `coel-hub auth`'s `authenticated` event the greeter settles
  back into it and answers "go"; the hub waits up to 0.8 s, then starts the session. That frame
  stays up (frozen) on the session VT until Hyprland draws, so it reads as a splash. The
  greeter resets to normal 2 s later (it stays on VT1 for lock/logout).
- Hyprland's pre-wallpaper frames are plain #282c34 (hyprland.lua `misc`, no logo/splash).
- Session side (`desktop/SessionIntro.qml`; real login only: not a reload, Hyprland < 20 s old)
  opens on the picture and dissolves into the desktop; `DeskState.introActive` holds the
  greeting. `ipc call sessionintro test` replays it.
- Splash -> greeter handoff with no black: modules/boot-splash.nix (header explains the
  steps; Plymouth is deactivated, not quit, until the greeter touches
  /run/coel-hub/greeter-drawn). VM test: `tests/run.py boot-seam` grabs frames from power-on
  and fails on any black one after the splash. Plain `--retain-splash` on the stock
  plymouth-quit once caused a black, hung boot; don't go back to that.
- Session hosts never touch the screen: `switch = false` plus patches/greetd-host-no-vt-wait.patch
  (stock greetd switches to its VT at startup and waits there, which flashed VT7/VT8 black after
  the splash). `coel-hub auth` activates the new session itself (`activate_new_session`), and
  waits up to 0.8 s after `authenticated` for the greeter's "go". VM test: `tests/run.py
  session-hub`. The black flash on first lock (session -> VT1 switch) is still there.
- hypridle 0.1.7 ignores `-c` until a config exists in a default location; home/hypridle.nix
  renders into a private dir on XDG_CONFIG_DIRS (it crash-looped from Nov 18 until this).

## Sounds (`services/Sounds.qml`)

- A pack is a folder of WAVs named by event (list: `ipc call sounds list`); default is
  `assets/sounds/synth/`, generated by `sounds/synth.py` (edit there, rerun; don't hand-edit
  WAVs). `settings.toml [sounds] pack` points at another folder; missing names fall back.
- Plays through QtMultimedia SoundEffect, which Quickshell only has via the overlay in
  configuration.nix; without it (e.g. before a switch) it falls back to `pw-play`.
  `ipc call sounds status` says which, and why it's silent (mode `sounds = false`, eye candy).
- The lock screen is its own process: it asks the main shell to play lock/unlock over IPC.
- Volume is on a 5% grid everywhere (OSD keys and sliders round DOWN onto it).

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

- **Desktop cards**: see "Modes and the desktop". Data in `~/.local/share/coel/`
  (`COEL_DATA_DIR` overrides). `widgets/` now only holds shared primitives (Pal, Mono, Box,
  ...) and `KanbanEditor`. Needs the Phosphor-Fill font. IPC: `... call widgets toggle|newcard`.
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

# CoelOS Quickshell bar — project status

Handoff doc written for a future session (or you) to pick this up with
zero conversation history. Everything here reflects real, verified state
as of **2026-09-29**, not aspiration. Supersedes the previous version of
this file — the lock/login work described below (this doc's own previous
version, itself now committed) is done; this update's real news is the
**rofi retirement + misc cleanup** section, all still uncommitted.

**Update, 2026-09-30 (not this doc's original session):** the rofi
retirement pass below got committed (`b96ce68`), so it's no longer
uncommitted as the rest of this doc says. Since then: `home/waybar.nix`
and its assets were deleted outright (waybar is now fully gone, not just
unused); a documentation/comment-cleanup pass trimmed verbose comments
across most `.nix` files and fixed several stale references this doc's
own "left no dangling references anywhere real" claim missed (the
`pamtester` claim in `configuration.nix`'s lock-PAM comment was wrong —
the real backend is `PamContext`, see `AuthBackend.qml`'s own comment);
and the orphaned in-app "about" view this doc flagged below (`AboutBackend`/
`aboutView`/`view` in `LauncherPanel.qml`) was removed entirely, along with
the same dead `hyprlock`-direct-call pattern found a second time in
`sysPanel/dropdowns/PowerDropdown.qml`'s session actions (not just the
launcher's "Lock" entry this doc originally caught) — both now call the
real `quickshell -p .../lock-real-shell.qml` command.

Commit history: `git log`, most recent relevant commits `0344391`,
`ec76ac3`, `26871ef` for the bar/launcher work, `54c1a5e`/`6e27aba` for the
start of the lock+login work, and **`41c81d6`** (the previous version of
this doc, plus the full greeter real-hardware debugging arc) is now
committed. **As of this doc, there are real uncommitted changes on top of
`41c81d6`** — the user hasn't committed since. Currently modified/deleted
(per `git status`), all from the same pass, **none of it touched by this
session** (found while re-reading the repo to write this update, not
something Claude did):
- `home/rofi.nix` and every `home/rofi/scripts/*.sh` **deleted entirely**,
  plus the `netpala`/`bluepala` flake inputs and their home-manager
  modules (`home/netpala.nix`, `home/bluepala.nix`, `flake.nix`,
  `flake.lock`, `home.nix`) — see the new section below.
- `home/purge.nix` — reworked its `EXIT` trap into a named function
  (`hold_open`), no behavior change.
- `home/quickshell/launcher/LauncherPanel.qml` — "About this system" no
  longer opens the launcher's own in-app about view, and "Purge" now
  calls the real `coel-purge` wrapper instead of an inlined command — see
  below, including a real orphaned-code finding this uncovered.
- `home/hyprland.nix` — one window-rule size tweak (`float-info-terminal`,
  1111x725 → 1144x655), presumably retuned for fastfetch's own output
  now that "About this system" opens it directly in that floating
  terminal instead of the launcher's in-app view.

Verified this pass: the whole config still builds clean (`nix build
.#nixosConfigurations.coelos.config.system.build.toplevel --no-link`)
with all of the above in place — the rofi/netpala/bluepala removal left no
dangling references anywhere real (a few stray *comments* elsewhere in
`home/hyprland.nix`/`home.nix` still mention `home/rofi.nix` by name as
historical context for why certain keybinds/window rules exist; harmless,
not chased down).

## What this project is

A from-scratch Quickshell (Wayland, Hyprland) top bar + popups + launcher,
replacing waybar and rofi, built phase-by-phase against a Claude-Design
HTML mockup at **`Quickshell Example/Quickshell Bar.dc.html`** (repo root).
That file is the source of truth for visual/behavioral design — when in
doubt about how something should look or behave, read it before guessing;
it also has a companion **`Quickshell Example/support.js`** which, despite
the name, is unrelated templating/DOM-manipulation plumbing for the mock
page itself, *not* app logic to port (learned this the hard way looking
for a "conversion system" there that didn't exist — it was in the `.dc.html`
file's own inline `<script>`, see Convert.js below). **The user actively
edits the mock file themselves** to add new reference pages/screenshots
for upcoming work — don't treat unstaged changes there as stray, and don't
overwrite them.

Established build pattern per feature: **hardcoded/real-content UI first
(signed off via screenshots)**, **then real logic** (subprocess calls, live
state) **in a separate pass**. Validation pipeline used throughout:
1. `qmllint` (paths for the Qt/Quickshell qml dirs are in shell history;
   real syntax errors matter, "unqualified access"/`PanelWindow is not
   creatable` are expected noise this codebase already has everywhere) —
   in practice this session, bare `qmllint <file>` without those import
   paths just spams "Failed to import ..." noise and isn't useful; rely on
   the live instance's own log instead (next point) unless you've got the
   real import-path flags to hand.
2. The user runs a **live, production** quickshell instance (their real
   Hyprland session, not a throwaway dev copy) that auto-hot-reloads on
   QML edits. Validate via `quickshell ipc -p ~/.nixos/home/quickshell
   show` (confirms the instance is alive and responsive) and by tailing
   `/run/user/1000/quickshell/by-id/*/log.qslog` for `WARN`/`error` lines
   right after an edit. **Never `pkill`/relaunch this process without
   asking first** — it's the user's actual live panel, not a disposable
   dev instance; there's no way to tell them apart by command line alone,
   and killing it blind has bitten a previous session already.
3. For Nix-level changes (module/home-manager files, not plain QML), `nix
   build .#nixosConfigurations.coelos.config.system.build.toplevel
   --no-link --print-out-paths` verifies the whole config evaluates and
   builds *without* switching anything live — safe to run freely. Actually
   switching (`nixos-rebuild switch` or equivalent) is the user's own call,
   same as committing — they run it themselves; some changes (Nix-level
   ones, systemd unit/service edits, anything needing a process restart
   rather than a QML hot-reload) only take effect after they do.
4. `git add -- <specific files>` (never bare `-A`) if asked to stage —
   **the user commits themselves**, never commit unasked. In practice this
   whole project's history shows the user commits in large, infrequent,
   loosely-described batches (see `git log`) rather than per-feature, so
   don't expect or wait for a commit to "confirm" a task is accepted.

Popup-content Timers/Processes are generally gated on a `popupOpen`/
similar prop that's false while the dropdown is closed — to validate real
logic that only runs while open, either get the user to actually open it,
or temporarily force the gate on with a clearly-marked `// TEMP` comment,
confirm, then revert before considering the change done.

Also see `AGENTS.md` (repo root) for the Nerd-Font-glyph rule: several
files elsewhere in this repo (**not** anything under `home/quickshell/`)
contain real private-use glyphs invisible to Claude and must be edited
with `Edit`+ASCII-only anchors, never `Write`/full retype. Everything
under this directory goes through `Phosphor.js`'s codepoint table instead
(see below) — real icon codepoints there should be verified against an
actual source (`/tmp/phosphor_icons.ts`, if still present, has the full
Phosphor icon-set name→codepoint table; used this session to look up
`arrows-left-right`'s real codepoint (`0xe0a0`) rather than guess it), not
invented.

## Architecture map

```
home/quickshell/
  shell.qml               top-level: owns launcherOpen/launcherScreen state,
                           instantiates Panel + Border + Launcher
  Border.qml               screen-edge decorative frame (own PanelWindow,
                           WlrLayer.Top)
  Launcher.qml              full-screen Spotlight overlay chrome (scrim +
                           centered card), IpcHandler for Hyprland keybinds,
                           per-screen Variants
  launcher/
    LauncherPanel.qml       the big one -- moved here from
                           sysPanel/dropdowns/ this arc specifically
                           because it isn't a dropdown (own PanelWindow
                           chrome via Launcher.qml, not Popup.qml). Owns
                           category/search construction (buildCategories(),
                           fuzzyList()), keyboard handling, selection/scroll,
                           the clipboard live-preview Processes, and the
                           full visual tree. Instantiates every backend
                           below as a plain child Item with an `id`.
    backends/               one Item-per-data-source, each exposing plain
                           properties/functions LauncherPanel.qml reads --
                           AppsBackend, SshBackend, ClipboardBackend,
                           EmojiBackend, TogglesBackend, AboutBackend,
                           CurrencyBackend (new, live currency rates --
                           see below)
  scripts/
    list-apps.py             real .desktop file parser for app search
    list-ssh-hosts.py        real ~/.ssh/config parser for the ssh category
    update-emoji-data.py     fetches/caches current emoji data from
                           unicode.org
  sysPanel/
    Panel.qml               the actual bar; owns openPopup (per-screen,
                           now includes "tray") and trayMenuItem (which
                           SystemTrayItem the tray dropdown is showing),
                           bubbles launcherToggleRequested/openPanelRequested
    Popup.qml                shared dropdown chrome (right/center-anchored
                           under the bar) for every button-triggered popup,
                           tray included now
    Calc.js                  calculator expression engine (ported from the
                           mock's calcEval())
    Convert.js                unit/currency converter (new -- ported from
                           the mock's convEval(), see below)
    Phosphor.js               icon name -> codepoint table
    dropdowns/                AudioDropdown, BluetoothDropdown,
                           NetworkDropdown, PowerDropdown, SystemDropdown,
                           CalendarDropdown, TrayDropdown (new, see below)
    buttons/                  bar chips: Battery, Bluetooth, Button, Buttons,
                           Clock, Cpu, Logo, Network, Tray, Volume,
                           Workspaces
    components/                shared row/UI bits: BulletDivider, CoreRow,
                           DeviceRow, DiskRow, FormField, PortRow,
                           ProcessRow, Section, Sparkline
```

## Phase status (the 6 original bar dropdowns + calendar)

All done, real-data-wired, long since built and screenshot-verified:
**Network, Audio, Bluetooth, Power, System monitor, Calendar + todo**.
Calendar's todos persist in real SQLite via `QtQuick.LocalStorage`.

## Launcher (rofi replacement) — overall status

Fully replaces rofi's categorized dmenu (`coel-main-menu`) and `rofi -show
drun`. Originally `rofi.nix`'s own scripts were left untouched with only
the Hyprland keybinds repointed (`$mainMod space`/`$mainMod shift+space`
→ `quickshell ipc -p ~/.nixos/home/quickshell call launcher toggle`,
`$mainMod V` → `... call launcher openClipboard`, `$mainMod .` → `... call
launcher openEmoji`) — **since resolved**: `rofi.nix` and every one of its
scripts are now deleted entirely (see "Rofi retirement + misc cleanup"
below), not just the emoji picker question this used to leave open.

Categories as of now, in search-priority order (see "search ordering"
below for what that means): **launch, ssh, actions** (merged
toggles+capture, see below), **convert** (new), **clipboard** (real
`cliphist` category, live-decode preview), **math, system** — plus
**emoji** (search-only from the main launcher, browsable+recency-tracked
in `super+.`'s emoji-only mode) which isn't a `categories` entry at all,
matched separately.

### Launcher restructure: LauncherPanel moved out of dropdowns/

Per explicit request: "The LauncherPanel.qml file shouldn't be under
dropdowns since it's not a dropdown." Moved to its own `home/quickshell/
launcher/` directory with a `backends/` subfolder holding one
Item-per-data-source component each (AppsBackend, SshBackend,
ClipboardBackend, EmojiBackend, TogglesBackend, AboutBackend). Confirmed
working post-move via a real cold-launch log the user pasted (was
genuinely uncertain beforehand whether Quickshell's hot-reload handles a
full directory move/deletion the same way it handles an in-place edit —
it does).

### ssh category (real, `~/.ssh/config`-backed)

`scripts/list-ssh-hosts.py` parses the real config (skips pattern/multi-
alias `Host` lines), outputs name/user/host/port/identityFile as JSON.
Enter opens `ghostty -e ssh <alias>`; Shift+Enter copies the ssh command.
Name-based blacklist mechanism exists (`SshBackend.blacklist`, currently
`["proxy", "testing-vm"]` — **the user edited this list themselves**
after it initially shipped empty, don't assume it's still empty).

### actions category (merged toggles + capture)

Per explicit request: "merge toggles and captures into one actions
category." Single `{ id: "actions", label: "actions", icon: "lightning" }`
now holds DND/keep-awake/mic-mute/monochrome/eye-candy toggles *and*
screenshot/screen-record/color-picker. Each item carries a `groupLabel`
("toggles" or "capture") so browsing the category (no search query) still
shows the same kind of header "topper" emoji-browse-mode already had —
see next point.

**Category header toppers, generalized**: the `rows` computed property's
grouping used to only activate `if (hasQuery || searchScope !== "")`. Now
also activates whenever `list.some(it => it.groupLabel)` — i.e. any
browsed category whose *items themselves* opted in by setting
`groupLabel`, not just search results or an active scope restriction. This
is what makes the actions category show "toggles"/"capture" headers while
just browsing it with no query, the same mechanism (not a special case)
as emoji's own "recently used" grouping.

**Toggles**: DND (real, `makoctl mode -t dnd`), keep awake (real,
`systemd-inhibit` child process), mic mute, monochrome (real, Hyprland
`decoration:screen_shader` live-toggled against `scripts/monochrome.frag`,
a luminance-weighted grayscale GLSL shader), eye candy (real, live
`hyprctl keyword` toggling of animations/blur/rounding/borders). **Night
light and charge limit were removed entirely** per explicit user decision
after real hardware testing showed the Framework 13 AMD's charge-limit EC
override doesn't survive a reboot (BIOS's own value is separate/
persistent, the runtime override isn't) — don't re-add either without
being asked; a `framework-laptop-kmod` integration for this was built,
tested, and then **fully reverted** (module deleted, import removed) for
the same reason.

### convert category (new: real unit + currency converter)

Per explicit request, ported from the mock's `convEval()` (found in the
`.dc.html` file itself, *not* `support.js` — see the top-of-file note
about that dead end). `sysPanel/Convert.js`: `evaluate(raw, liveRates,
ratesUpdated)`, a pure function verified against the mock's own example
expressions via Node before trusting it live. Handles length, mass, data,
time, speed, volume, temperature, and currency — parses `"5 km to mi"`,
`"72 f to c"`, `"$120 to eur"`, `"180 lb"` (bare unit → a sensible default
target), plural/alias unit names, currency symbols (`$€£¥`).

**Currency rates are live, not static** — the user explicitly rejected a
first pass that hardcoded rates ("Fetch currencies like the example
supposedly does. Do it every hour or so"). `launcher/backends/
CurrencyBackend.qml` fetches `https://open.er-api.com/v6/latest/USD` (free,
no API key, ~160 currencies — chosen over ECB-based sources like
frankfurter.app specifically because those don't cover most of Latin
America, which is what prompted this: the user tested MXN/ARS/COP/CLP/PEN/
BRL and got no results from the first, hardcoded-table version) on launch
and every hour via a `Timer`. `Convert.js`'s own hardcoded table (now
includes those six Latin American currencies too) only serves as a
fallback for before the first fetch resolves or if a fetch ever fails —
live rates override it entry-by-entry when available. The preview panel's
"source" row honestly shows which one was actually used
(`"live · updated <timestamp>"` vs `"fixed fallback, not live"`).

Same top-slot-winning precedence as the calculator (a valid conversion
always wins the top hit), and convert wins over calc if both would somehow
match, mirroring the mock's own `const c = cv ? null : calcEval()`. Own
browsable category with example conversions (`fill: true`, same pattern as
`math`'s examples).

### Search bangs (`@g`, `@ddg`, `@yt`)

Per explicit request, no dedicated category (there's nothing to browse
without a query, so a chip would only ever be empty). A `fuzzyList()`
early-return, same "clearly one thing, not a fuzzy match" pattern as the
calculator/emoji-scope branches: `@g <query>`/`@ddg <query>`/`@yt <query>`
becomes a single top-priority result that opens the search directly in Zen
(`command: ["zen", url]`).

### Search ordering (fixed twice this arc, both times per real complaints)

1. **Clipboard was outranking real matches** — e.g. typing "rebuild"
   surfaced clipboard history containing that word before the actual
   "Rebuild" system command, because `categories.forEach` had no
   cross-category score sort (only a single best-scoring item gets pulled
   to the top as `top:true`; everything else is pure insertion order).
   Fixed by moving the `clipboard` category to *last* in
   `buildCategories()`'s returned array — every other category's matches
   now sort ahead of it in mixed search results, while it still sorts
   ahead of emoji (which is unconditionally appended last regardless).
2. **Apps were outranking real matches too** — e.g. typing "orca"
   surfaced clipboard history before the installed app "OrcaSlicer".
   `apps.installed.forEach` used to run *after* `categories.forEach`
   (including clipboard) in `fuzzyList()`; swapped so apps are matched
   first. Current overall priority: **apps → other categories → clipboard
   → emoji**.

### Tray right-click menus (new, and a real dead-end en route)

Per explicit request: "Make it so that tray items can show their dropdown
menus on right click." The tray (`sysPanel/buttons/Tray.qml`) previously
only called `secondaryActivate()` on right-click with no real menu UI.

**First attempt, abandoned**: `QsMenuAnchor` (Quickshell's binding to the
native platform `QMenu`), bound directly to `SystemTrayItem.menu`. Worked
in principle but: (a) `.open()` throws unless quickshell was launched with
`//@ pragma UseQApplication` in the root QML file *and restarted* (not
hot-reloadable — this pragma was added then **reverted** once the native
approach was abandoned), and (b) even once working, it opened flush
against the very top of the screen blocking everything, with none of this
panel's own visual styling — a real platform popup, not a themed dropdown.

**What's actually built**: `sysPanel/dropdowns/TrayDropdown.qml`, a normal
`Popup.qml`-chrome dropdown like every other bar button, styled to match
(same row height/radius/hover treatment as e.g. Bluetooth's device rows).
Uses `QsMenuOpener` (bound to `trayItem.menu`) to resolve the real DBusMenu
into plain data (`.children`: text/icon/enabled/checkState/hasChildren per
entry) with **no native popup involved at all**. One level of submenu
expand/collapse supported inline (indented, same list, via a second
`QsMenuOpener` bound to the expanded entry itself — a `QsMenuEntry` is
itself a `QsMenuHandle`, which is what makes that work) — real tray menus
rarely nest deeper than that; not handled if they do.

`Panel.qml` gained `trayMenuItem` (which `SystemTrayItem` the dropdown is
currently showing) alongside the existing `openPopup` string, with a
*single* shared `Popup` instance reused across every tray icon (not one
each — icon count is unbounded/variable, unlike the fixed bar buttons).
Right-clicking a different icon while another's menu is open switches
straight to it rather than closing (had to guard against `openPopup ===
"tray"` alone, which doesn't distinguish "same icon again" from "different
icon"). `rightMargin: 268` for this popup is a rough estimate (same
"guess then refine" approach as every other dropdown's own rightMargin
here, per their existing comments) — not one that tracks the specific
icon clicked; a single fixed position for the whole tray group, since
there's no fixed pixel offset that could track a variable-count icon list
anyway.

**Two real bugs found and fixed against Steam's actual tray menu (live
user testing, not guessed)**:
- `entry.sendTriggered()` (listed as a real `Method` in Quickshell's own
  `.qmltypes` metadata) is **not actually QML-invokable** — threw
  `TypeError: ... is not a function` live. Fixed by calling
  `entry.triggered()` instead (`QsMenuEntry`'s own signal, not
  `DBusMenuItem`'s method) — Quickshell's DBusMenu backend listens for
  that internally and is what actually sends the real D-Bus Event call.
  Worth remembering generally: a `.qmltypes` `Method` entry isn't a
  guarantee of real invokability; trust a live `TypeError` over the
  metadata when they disagree.
- Fixed width (260px) clipped real menu text ("Steam Linux Runtime 1.0
  (scout)" lost its closing paren, confirmed via a real screenshot).
  Widened to 340px (Panel.qml's `contentWidth`, which is the *whole* popup
  frame including its fixed 32px side padding, not just the content area).

**Not yet confirmed live**: whether `sendTriggered`→`triggered` actually
makes a real Steam menu item (e.g. "Exit Steam") do the real thing when
clicked, and whether the widened popup is now wide enough for every real
entry — both fixes are reasoned-through and reload-clean (no QML errors),
but the user hadn't reported back on a live click-through test as of this
doc.

### Two real (if low-stakes) QML warning bugs fixed

Both found via the user pasting real `WARN scene:` log lines, not
speculative cleanup:
- `readonly property bool big: panelRoot.hasQuery && it.top` — JS `&&`
  returns its second operand as-is when the first is truthy, and most rows
  (everything that isn't the current top hit) simply never set `top` at
  all rather than setting it `false`. That evaluated to literal
  `undefined` for every such row, which QML can't assign to a
  `property bool` ("Unable to assign [undefined] to bool", once per row
  rendered). Fixed with `!!it.top`.
- The "about" page's `about.data.*` bindings occasionally logged "Unable
  to assign [undefined] to QString" specifically during a hot-reload
  cycle — `AboutBackend.qml` gets torn down/recreated on reload, and
  there's a brief window mid-recreation where sibling bindings
  re-evaluate against it before its `data` property (and the real
  system-info `Process` behind it) has settled back in. Self-heals within
  the same reload either way; added `|| ""` fallbacks on the consuming
  side (`LauncherPanel.qml`, not `AboutBackend.qml` — its own defaults
  were already complete) purely to stop the log noise.

## GlobalProtect / LUC VPN — long debugging arc, partially resolved

Separate from the launcher work above. Full history also lives in
persistent memory (`project_globalprotect_luc.md` in the memory system) —
this is the condensed version for anyone reading just this repo.

**Background**: `home/globalprotect.nix` (user agent, `coel-vpn-connect`/
`coel-vpn-status`/`coel-vpn-disconnect` wrapper scripts) and
`modules/globalprotect.nix` (system daemon) both run the vendored
GlobalProtect client inside a `pkgs.buildFHSEnv` bubblewrap sandbox
(`lib/globalprotect-fhs.nix`, shared by both). `home/globalprotect/
gp-connect.exp` drives the actual login (expect script, LUC auth is plain
portal username+password + a gateway MFA code, not SAML).

**The reported symptom**: connecting reliably failed via both the
Quickshell panel *and* direct CLI use with a generic, unhelpful
`auth-failed`/`unexpected-exit` status and no way to tell why.

**Root-caused, in order**:
1. `gp-connect.exp` had three genuinely different failure paths (password
   rejected 3×, MFA rejected 5×, and a catch-all `eof` branch for *any*
   unrecognized client exit) all emitting the identical `GP_STATUS:
   auth-failed` string — indistinguishable from the outside. Split into
   `password-rejected`/`mfa-failed`/`auth-failed`/`unexpected-exit`, the
   last of which now also logs what `globalprotect show --status` said to
   stderr. This is what actually let the real cause surface next.
2. With that in place, the real failure showed up as `unexpected-exit`
   with the vendor CLI's own message: *"Unable to establish a new
   GlobalProtect connection as a GlobalProtect connection is already
   established..."* — even though nothing was actually connected. Ruled
   out (each verified live, not guessed): a stale/persistent `gpd0` tun
   interface (found one with `persist on`, deleted it — didn't fix it),
   restarting both the user agent and system daemon (didn't fix it
   either).
3. **Actual root cause, found via `PanGPS.log`**: authentication was
   genuinely succeeding (SSL handshake, gateway accepted credentials) —
   the failure was immediately after, in `SetupNetwork()`/
   `InstallClientConfig()`, with `ioctl() failed on SIOCGIFFLAGS ...
   error=No such device`. Cross-checked `/proc/<PanGPS pid>/status`:
   `CapEff: 0000000000000000` — **zero effective capabilities** despite
   running as root with a full bounding set. Bubblewrap unconditionally
   sets `no_new_privs` before exec'ing the sandboxed program, which,
   combined with an empty inheritable capability set (the ordinary
   default) and no file capabilities on the vendor binaries, zeroes out
   the effective/permitted sets at exec time even for a root-run process —
   `PanGPS` genuinely had no privilege to create/configure its own tunnel
   interface. **Fix**: `--cap-add CAP_NET_ADMIN --cap-add CAP_NET_RAW` in
   `lib/globalprotect-fhs.nix`'s `extraBwrapArgs` (bwrap's own
   `--cap-add` only has any effect for a *privileged* caller, so this is a
   no-op for the per-user agent's own unprivileged sandbox — it's
   specifically for the root-run system daemon). Build-verified.
4. Separately, `globalprotect-agent` (the user systemd service, PanGPA)
   was found **dead** after a `nixos-rebuild switch` — it had exited
   cleanly (status 0) during the switch's own service restart and never
   came back, since `Restart = "on-failure"` doesn't cover a clean exit.
   Changed to `Restart = "always"` in `home/globalprotect.nix`.
   Build-verified.

**Not yet confirmed**: whether the capability fix actually resolves real
connect attempts end-to-end (the "already established" symptom was last
seen *before* this fix was live — the user hadn't reported back on a real
post-rebuild connect attempt with both fixes in place as of this doc).
Also still outstanding, asked twice, never answered: whether the user's
own uncommitted-at-the-time (now presumably committed, not re-checked)
removal of the `"OnDemand"` status case from `coel-vpn-status`'s parsing
was intentional — flagged as a possible regression (would read "unknown"
instead of "connected" if GP ever reports that mode). And a separate,
never-revisited thread: connecting to LUC's GlobalProtect was reported to
break this Claude Code session's own network connectivity — hypothesized
as full-tunnel-by-design (distinct from an already-fixed, genuine local-
subnet route-hijack bug), never actually diagnosed since it can't be
tested from inside the session it breaks.

## Lock screen + greetd login screen — built and validated on real hardware

Replaces `hyprlock` (lock) and SDDM (login/greeter) with a custom
Quickshell/QML UI matching an HTML mockup (`sddm-hyprlock/Lockscreen.dc.html`,
layout "1a Corner"). Both are now real, working, and have been exercised
repeatedly on the user's actual hardware (not just a VM) — this section is
long because getting the greeter working was a genuinely long debugging
arc with a lot of root-caused, non-obvious fixes; skip to "Current status"
below if you just need the summary.

### Lock screen (`home/quickshell/lock/`)

Built hardcoded-UI-first (screenshot-verified against the mockup), then
wired to a real backend, matching this project's own established
convention. Components: `ClockDate`, `NetworkBattery`, `MediaWidget`,
`AuthCard` (all in `lock/components/`), composed by `LockScreen.qml`
(pure layout, props-down/signals-up) and owned/stated by `Lock.qml`.

**Auth backend** (`lock/backends/AuthBackend.qml`): real `PamContext`
(`Quickshell.Services.Pam`), *not* the `pamtester` subprocess an earlier
session mistakenly believed was necessary (no native PAM binding was
thought to exist — it does). Two **independent, parallel** `PamContext`
instances against two dedicated single-purpose PAM services
(`configuration.nix`): `quickshell-lock` (`fprintAuth = false`, password
only) and `quickshell-lock-fp` (`unixAuth = false`, fingerprint only,
restarts itself on every failure via a debounced `Timer` so it's always
listening, not click-triggered). Running two single-purpose stacks in
parallel, rather than one shared stack with both modules, is a deliberate
choice — a shared stack has an inherent "password waits behind the
fingerprint conversation" ordering problem (see the greeter section below,
which hit exactly this before being fixed the same way).

**Real session lock**: `Quickshell.Wayland`'s `WlSessionLock`/
`WlSessionLockSurface` (the real `ext-session-lock-v1` protocol), with a
dev-harness/real split (`lock-shell.qml` vs `lock-real-shell.qml`, both at
the Quickshell config root — Quickshell sandboxes each config to its own
root directory, which is why these can't live inside `lock/` itself)
mirroring the greeter's own real/mock duality.

**A real stuck-lockscreen incident, fixed**: `sessionLock.unlock()` is
listed as a real `Method` in Quickshell's `.qmltypes` metadata but isn't
reliably invokable — the same class of bug as the tray menu's
`sendTriggered()`/`triggered()` mixup earlier in this doc (metadata
claiming something is callable is not a guarantee). Fixed by using the
guaranteed-safe property assignment `sessionLock.locked = false` instead,
followed by a short `quitTimer` before `Qt.quit()`. Also added real
stderr/PAM-error surfacing so a genuinely broken backend produces a clear
message instead of a wrong-password-indistinguishable hang.

**Fingerprint UI**: per explicit request ("an icon displayed to denote
whether or not a fingerprint is registered rather than a trigger"), the
icon is a passive availability indicator (`AuthCard.fpOn`, sourced from
`AuthBackend.fingerprintEnrolled` via a real `fprintd-list <user>` check —
no native Quickshell fprintd service exists, so this one piece still
shells out), not a button — nothing to click, matching real hyprlock's own
always-on native backend.

**Security-reviewed**: ran the real `/security-review` skill/methodology
against this work before trusting it as an actual lockscreen. Clean — no
HIGH/MEDIUM findings.

### Login screen / greeter (`home/quickshell/greeter/`, `modules/greeter.nix`)

Architecture: `greetd` (login manager) → `cage` (minimal kiosk Wayland
compositor, no desktop session of its own) → `quickshell` → this app.
Reuses the lock screen's own components directly (`LockScreen.qml` with
`mode: "login"`) rather than a parallel visual design, so the two stay
identical-looking by construction. `GreeterBackend.qml` wraps
`Quickshell.Services.Greetd` (`createSession`/`respond`/`launch`,
`authMessage`/`authFailure`/`readyToLaunch`) the same "backend exposes a
plain interface, UI never touches the auth system" shape as the lock
screen's own `AuthBackend.qml`. `modules/greeter.nix` is gated behind
`services.qs-greeter.enable` (currently **`true`** in `configuration.nix`)
and disables SDDM via `mkForce false` when active — the previous
(SDDM-based) generation stays selectable in the bootloader menu as a real
fallback.

Real `users.json`/`sessions.json` are generated at build time from
`config.users.users` (normal users only) and the real installed
`wayland-sessions/*.desktop` files (`config.services.displayManager.
sessionData.desktops`) — both Hyprland and Plasma are selectable, matching
the previous dual-session SDDM setup. A `mock` mode (auto-enabled whenever
`Greetd.available` is false) lets the whole UI be built and screenshot-
verified in an ordinary window (`greeter-shell.qml`) before any of the
NixOS/greetd wiring existed at all.

**This took a long real-hardware debugging arc to get right — the fixes,
roughly in the order they were found (each one genuinely necessary, not
speculative):**

1. **`PanelWindow`/`WlrLayershell` → plain `FloatingWindow`.** The lock
   screen's own chrome uses `PanelWindow` (real `wlr-layer-shell`) because
   it runs under Hyprland, which implements that protocol. `cage` doesn't
   — confirmed live that cage/quickshell were both genuinely running (not
   crashed) but produced zero visible frame, because the layer-shell
   surface request was silently never satisfied. A plain `FloatingWindow`
   (an ordinary `xdg-toplevel`) is what a kiosk compositor like cage
   actually expects.

2. **`width`/`height` → `implicitWidth`/`implicitHeight`.** Quickshell
   itself logs "Setting `width` is deprecated. Set `implicitWidth`
   instead." for `FloatingWindow` — plain `width`/`height` silently didn't
   take effect as the real size hint at all. This had been masked in the
   windowed dev harness because Hyprland's own tiling WM assigned the
   window *some* other size regardless of what was requested, which
   happened to be big enough to look correct.

3. **A genuine `cage` startup race: output enumeration vs. client
   connect.** Even with sizing fixed, real hardware logs showed Qt
   creating a placeholder screen ("There are no outputs") and
   `eglSwapBuffers` failing on a literal null surface (`EGL_BAD_SURFACE`)
   — on a *completely clean* single-compositor boot, with the correct
   seat backend, with only one real GPU/output. DRM-master contention
   with another compositor, `seatd` vs `logind` (`LIBSEAT_BACKEND=logind`
   is still set in the launcher script as a reasonable simplification,
   since `logind` is what this laptop's real sessions already use daily —
   but it turned out *not* to be the actual fix), and a wrong/missing DRM
   device were all directly ruled out on real hardware, one at a time.
   What actually fixed it: a **1-second `sleep`** before quickshell
   connects (`cage -- bash -c "sleep 1; exec quickshell ..."`), giving
   cage's own backend time to finish enumerating the real output before
   the client ever asks for one.

4. **`greetd.service`'s default `Type=idle` added a real ~6s boot
   delay.** Confirmed via precise journal timestamps: `Type=idle` defers
   actual execution until other boot jobs are dispatched, capped at a
   documented, hardcoded 5s systemd timeout either way — this is real,
   intentional systemd behavior (meant to avoid interleaving console
   output between services starting in parallel), not a bug. SDDM never
   showed this gap because its own splash covers the console immediately;
   cage has nothing covering it, so the deferral was a visible black
   screen. Fixed with `systemd.services.greetd.serviceConfig.Type =
   lib.mkForce "simple"`.

5. **Two separate sources of a console text flash during the greeter →
   session handoff**, both fixed by redirecting output to a log file
   instead of letting it hit the bare VT: cage's own `-d` debug logging
   (→ `/tmp/qs-greeter-cage.log`, in the launcher script) and the
   launched session's own startup logging, Hyprland's especially verbose
   (→ `/tmp/qs-greeter-session.log`, via wrapping `Greetd.launch`'s
   command in `["/bin/sh", "-c", "<exec> >logfile 2>&1"]` in
   `GreeterBackend.qml`'s `doLaunch()`).

6. **Plasma specifically failed to launch (instant black-screen bounce
   back to the greeter)** — two independent bugs, both found via that
   session-log redirect:
   - **Wrong `XDG_CURRENT_DESKTOP` value.** `doLaunch()` was deriving it
     from the session's own filename-derived `id` (`"plasma"`,
     `"hyprland"`) instead of the `.desktop` file's real `DesktopNames=`
     field (`"KDE"`, `"Hyprland"`). Hyprland's own startup script
     self-corrects (and was what originally prompted, wrongly, removing
     this variable entirely — that had only ever been masking a
     wrong-*value* problem, not a should-be-unset one). Plasma has no
     equivalent self-correction and depends on the real value for
     portals/Qt theming/KDE component detection. Fixed by extracting the
     real `DesktopNames=` line in `modules/greeter.nix`'s session-JSON
     generation and using it in `GreeterBackend.qml`.
   - **Missing `PATH`.** Plasma's session died in ~34ms with zero
     output — an instant `exec` failure, not a crash. Its own
     `plasma-dbus-run-session-if-needed` script (unlike Hyprland's, which
     hardcodes full Nix store paths throughout) execs the bare command
     name `dbus-run-session`, relying on `$PATH`. `Greetd.launch()`
     doesn't inherit a normal login shell's `PATH` setup. Fixed by
     explicitly passing `PATH=/run/current-system/sw/bin` (the standard
     NixOS location every system-wide package, including `dbus`, is
     symlinked into).

7. **Wrong default session.** `hyprland-uwsm.desktop` sorts before
   `hyprland.desktop` alphabetically (`-` < `.` in ASCII) in the shell
   glob `modules/greeter.nix` builds the session list from, silently
   making the uwsm-managed session the default instead of plain Hyprland.
   Fixed in `GreeterBackend.qml` by explicitly looking up the `"hyprland"`
   id rather than defaulting to index 0.

8. **Password login looked broken; fingerprint "worked" instantly.**
   `security.pam.services.greetd` had fprintd auth enabled by default
   (same as everything else on this system), tried automatically before
   `pam_unix` — a typed password just sat queued behind an unrequested,
   invisible "place your finger" step until fprintd's own ~30s timeout
   elapsed. First fixed by disabling it (`fprintAuth = false`) to make
   password reliable; then, per explicit follow-up request, **properly
   re-enabled** with real UI support instead of just avoided: the
   informational PAM message ("Place your finger on the fingerprint
   reader") now surfaces as real status text via the same
   `onAuthMessage`/`statusLine` plumbing the lock screen uses, and
   `AuthCard`'s fingerprint icon (`fpOn`) is wired to a real, per-selected-
   user `fprintd-list` enrollment check (the greeter can switch between
   accounts, unlike the lock screen, so this re-runs on
   `selectedUserChanged`) instead of being hardcoded `false`. Known
   remaining tradeoff, not yet addressed: a password-only login attempt
   still waits behind fprintd's own ~30s timeout if the sensor is never
   touched — now at least visible on screen instead of silent.

9. **UI polish, real hardware feedback**: `AuthCard`'s session-switcher
   label had a hardcoded `width: 64` never sized against real session
   names (`"Hyprland (uwsm-managed)"` needs ~165px at that font size),
   overflowing into the right-caret arrow — widened to 220px + `elide`.
   `MediaWidget` and the wifi chip are hidden in login mode
   (`mode !== "login"` / `NetworkBattery.showNetwork`) since neither has
   real meaning before a session exists; the **battery chip stays**, and
   is now wired to real `Quickshell.Services.UPower` data (same pattern
   `sysPanel/buttons/Battery.qml` already uses) instead of a static `82`
   placeholder that, it turned out, had never been real for the lock
   screen either until this pass.

**Current status**: fully working on real hardware — fast boot-to-greeter
(no more `Type=idle` delay), no console text flashes, correct default
session, both Hyprland and Plasma launch successfully, and both password
and fingerprint authenticate for real. Verified across many real
`sudo nixos-rebuild boot --flake ... && sudo reboot` cycles (never an
explicit `switch` — `boot` plus an actual reboot has the same practical
effect of making it the running default, just without a ceremonial
`switch` invocation). Security-reviewed (see above) with no findings.

**Known open items**:
- fprintd's ~30s timeout (point 8 above) — not shortened, just made
  visible. Revisit if a fast password-only login still feels too slow in
  practice.
- Avatar images (`greeter/assets/<username>.png`) — the greeter user
  can't read `~/.face`; would need images baked into the Nix store
  per-user. Non-urgent, never requested.
- ~~The launcher's own "Lock" entry... still runs `hyprlock` directly~~ —
  **fixed 2026-09-30**, along with the same pattern in
  `PowerDropdown.qml`'s session actions (not mentioned when this was first
  found); both now call `quickshell -p .../lock-real-shell.qml` directly.
- Plasma's own separate Look-and-Feel lock-screen adapter is explicitly
  out of scope (this project's lock screen replaces hyprlock/Hyprland's
  own locking, not KDE's).

## Rofi retirement + misc cleanup (uncommitted, not this session's work)

A separate pass, unrelated to the lock/login work above, found while
re-reading the repo to write this update — **not something Claude did**,
just documented here so it isn't mistaken for stray state. All still
uncommitted as of this doc; the whole config still builds clean with it
in place (verified this pass).

**Rofi fully removed.** `home/rofi.nix` (529 lines) and all six of its
`home/rofi/scripts/*.sh` helpers (`actions-menu`, `coel-package-search`,
`coel-screenrecord`, `coel-screenshot`, `config-menu`, `power-menu`,
`settings-menu`) are deleted outright, not just unimported — the Hyprland
keybinds that used to point at them were already repointed at the
Quickshell launcher in an earlier arc (see "Launcher" above), so this is
the actual final retirement, resolving that section's long-open "whether
to retire `coel-emoji-picker`" question by removing the whole rofi setup
it was part of, not just that one piece.

**`netpala`/`bluepala` also removed** — same pass, same cleanup, unrelated
to rofi specifically. These were terminal-UI network/Bluetooth tools
(`github:joel-sgc/netpala`, `github:joel-sgc/bluepala`, both the user's own
repos) wired in as home-manager modules; both flake inputs, their
`home/netpala.nix`/`home/bluepala.nix` modules, and the corresponding
`home.nix` import lines are gone, with `flake.lock` pruned to match.
Presumably superseded by the panel's own real `NetworkDropdown`/
`BluetoothDropdown` — not confirmed with the user, inferred from timing
and the fact that nothing else changed to replace them.

**`home/purge.nix`** (new module, the backing for the "Purge" launcher
entry added alongside the greeter work): a `coel-purge` wrapper script
(`pkgs.writeShellApplication`) running `sudo nix-collect-garbage -d` and
holding the terminal window open afterward (via an `EXIT` trap) whether it
succeeds or fails — the direct replacement for `coel-show-done`, a rofi.nix
helper that no longer exists now that rofi itself is gone. This pass
reworked that trap from an inline one-liner into a named `hold_open`
function; no behavior change.

**`LauncherPanel.qml`'s system category, two real changes**:
- "Purge" now calls the real `coel-purge` wrapper instead of the inlined
  `sudo nix-collect-garbage -d` the previous commit shipped it with.
- "About this system" changed from `view: "about"` (opening the
  launcher's own in-app about page, `AboutBackend.qml`'s data rendered
  inline) to a plain `command:` that runs `fastfetch` directly in a
  floating ghostty window instead. This orphaned the in-app about-view
  code (`AboutBackend { id: about }`, `view`/`aboutView` state, the
  about-page rendering block, and the generic `it.view`/`cur.view`
  plumbing that turned out to only ever have been used for this one case)
  — **removed entirely 2026-09-30**, including deleting
  `launcher/backends/AboutBackend.qml` itself, since nothing else
  instantiated it.

**`home/hyprland.nix`**: one window-rule size tweak for the
`com.joelsgc.info` floating terminal class (1111x725 → 1144x655),
presumably retuned to fit fastfetch's own output now that this class is
what "About this system" opens directly, rather than a leftover from
something else.

## Immediate next steps

The lock screen + greeter work is **done and committed** (`41c81d6`). The
rofi retirement + cleanup pass above is real but **uncommitted** and not
this session's work. No single stated top priority right now; treat the
open items below on their own merits if asked, in rough likely-relevance
order:

1. ~~Commit the rofi-retirement/cleanup pass~~ — done (`b96ce68`).
2. ~~Confirm whether dropping the in-app "about" view... should actually be
   removed~~ — removed entirely 2026-09-30 (see the top-of-file update
   note).
3. fprintd's ~30s timeout on the greeter (see the lock/login section's
   "Known open items") — revisit if a fast password-only login still
   feels slow without touching the sensor.
4. ~~The launcher's stale "Lock" entry still calls `hyprlock` directly~~ —
   fixed 2026-09-30, along with the same pattern in `PowerDropdown.qml`.
5. Live-test the tray dropdown end-to-end against a real menu click (does
   `entry.triggered()` actually perform the real action?) and confirm the
   340px width is enough for whatever else shows up in real tray menus
   beyond Steam's.
6. Live-test a real GlobalProtect connect attempt now that both the
   capability fix and `Restart = "always"` are in place — the underlying
   cause of the "already established"/interface-setup failure was
   root-caused and fixed, but never confirmed working end-to-end
   afterward.
7. Decide (asked twice already) whether to revert the `"OnDemand"` status
   case removal in `coel-vpn-status`.
8. The `Border.qml` `bgColor`-as-`borderColor` binding in `shell.qml` is
   *not* a bug — user confirmed live the opaque border is intentional,
   already settled, don't revisit.

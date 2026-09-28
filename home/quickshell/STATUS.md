# CoelOS Quickshell bar — project status

Handoff doc written for a future session (or you) to pick this up with
zero conversation history. Everything here reflects real, verified state
as of **2026-09-28**, not aspiration. Supersedes the previous version of
this file (2026-09-27) — that one described a batch of uncommitted work;
**all of it, plus everything below, is now committed** (see `git log`,
most recent relevant commits: `0344391`, `ec76ac3`, `26871ef`). Nothing in
this project is currently staged/pending — if you find uncommitted changes
in this directory, they're new since this doc was written, not leftover
from anything described here.

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
drun`. `rofi.nix`'s own scripts were left untouched, only the Hyprland
keybinds pointing at them changed (`$mainMod space`/`$mainMod shift+space`
→ `quickshell ipc -p ~/.nixos/home/quickshell call launcher toggle`,
`$mainMod V` → `... call launcher openClipboard`, `$mainMod .` → `... call
launcher openEmoji`). Whether to retire `coel-emoji-picker` entirely is
still an open call, not made unilaterally (unchanged from before).

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

## Immediate next steps

**The user's own stated next focus** (from the most recent commit
message): **a new lockscreen and login screen** — not more launcher/tray
work. Treat that as the priority unless told otherwise.

Genuinely open threads from the work above, in rough likely-relevance
order:
1. Live-test the tray dropdown end-to-end against a real menu click (does
   `entry.triggered()` actually perform the real action?) and confirm the
   340px width is enough for whatever else shows up in real tray menus
   beyond Steam's.
2. Live-test a real GlobalProtect connect attempt now that both the
   capability fix and `Restart = "always"` are in place — the underlying
   cause of the "already established"/interface-setup failure was
   root-caused and fixed, but never confirmed working end-to-end
   afterward.
3. Decide (asked twice already) whether to revert the `"OnDemand"` status
   case removal in `coel-vpn-status`.
4. Decide whether to retire/repoint `coel-emoji-picker` now that emoji
   search is native to the launcher (unchanged open question from before).
5. The `Border.qml` `bgColor`-as-`borderColor` binding in `shell.qml` is
   *not* a bug — user confirmed live the opaque border is intentional,
   already settled, don't revisit.

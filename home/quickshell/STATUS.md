# CoelOS Quickshell bar — project status

Handoff doc written right before a `/clear`, so a future session (or you)
can pick this up with zero conversation history. Everything here reflects
real, verified state as of **2026-09-27**, not aspiration.

## What this project is

A from-scratch Quickshell (Wayland, Hyprland) top bar + popups + launcher,
replacing waybar and rofi, built phase-by-phase against a Claude-Design
HTML mockup at **`Quickshell Example/Quickshell Bar.dc.html`** (repo root).
That file is the source of truth for visual/behavioral design — when in
doubt about how something should look or behave, read it before guessing.
**The user actively edits this mock file themselves** (it currently shows
as unstaged-modified in git) to add new reference pages/screenshots for
upcoming work — don't treat unstaged changes there as stray, and don't
overwrite them.

Established build pattern per feature: **hardcoded/real-content UI first
(signed off via screenshots)**, **then real logic** (subprocess calls, live
state) **in a separate pass**. Every change this whole project has gone
through the same validation pipeline before being called done:
1. `qmllint` (paths for the Qt/Quickshell qml dirs are in shell history;
   filter output to `syntax|non-existent|duplicate|property-override|
   cannot-specify-anchors|layout-positioning|\[error\]|type not found|is
   not a member` — everything else, incl. "unqualified access" and
   `PanelWindow is not creatable`, is expected noise this codebase already
   has everywhere).
2. Kill and relaunch the dev instance: `pkill -f "quickshell -c"` (verify
   stopped via `pgrep`), then `nohup env QML_DISABLE_DISK_CACHE=1
   quickshell -c ~/.nixos/home/quickshell > /tmp/quickshell-reload.log
   2>&1 &`, check the log is clean, check the process stays alive a few
   seconds (`ps -o etimes=`).
3. `git add -- <specific files>` (never bare `-A`) — **the user commits
   themselves**, never ask Claude to commit. Current staged-but-uncommitted
   work is listed below.
4. `nix eval .#nixosConfigurations.coelos.config.home-manager.users.joelsgc.home.activationPackage.drvPath`
   then `nix build "<drv>^*" --no-link --print-build-logs`.

Popup-content Timers/Processes are gated on a `popupOpen` prop that's
normally false; to validate real logic that only runs while a dropdown is
open, temporarily flip the relevant `property bool popupOpen: false` to
`true // TEMP: forced on for validation, reverting before commit`, cycle
the dev instance, confirm, then revert and cycle again before staging.

**Screenshot validation caveat**: this session used `nix run nixpkgs#grim`
(grim isn't installed by default; that's a one-off ephemeral fetch, not a
system change) to screenshot the live panel/popups for visual review,
reading the PNG back via the `Read` tool. **One of those screenshots
accidentally captured the user's actual browser window** (personal
content, not anything quickshell-related) instead of the panel. That
content was not examined or retained, but it means blind full-screen
`grim` captures aren't fully safe on this machine while the user is
multitasking — **ask before resuming screenshot-based validation**, or
default to qmllint+log+IPC-introspection-only validation instead.

Also see `AGENTS.md` (repo root) for the Nerd-Font-glyph rule: several
files contain real private-use glyphs invisible to Claude, and must be
edited with `Edit`+ASCII-only anchors, never `Write`/full retype. The
`sysPanel/*.qml` files created *this project* don't contain raw glyphs
(icons go through `Phosphor.js`'s codepoint table), but the rule is
unconditional for that whole path per `AGENTS.md` — ask before bulk-moving
or rewriting there regardless.

## Architecture map

```
home/quickshell/
  shell.qml              top-level: owns launcherOpen/launcherScreen state,
                          instantiates Panel + Border + Launcher
  Border.qml              screen-edge decorative frame (own PanelWindow,
                          WlrLayer.Top -- see "known oddities" below)
  Launcher.qml            NEW this session: full-screen Spotlight overlay
                          chrome (scrim + centered card), IpcHandler for
                          the Hyprland keybind, per-screen Variants
  assets/                 logo.svg, logo.png, Coel.svg
  scripts/
    list-apps.py          NEW: real .desktop file parser for app search
  sysPanel/
    Panel.qml             the actual bar; owns openPopup (per-screen) and
                          bubbles launcherToggleRequested/openPanelRequested
    Popup.qml             shared dropdown chrome (right/center-anchored
                          under the bar) for the 6 button-triggered popups
    Phosphor.js           icon name -> codepoint table (verified against
                          real phosphor-icons/core source, not guessed)
    dropdowns/            AudioDropdown, BluetoothDropdown, NetworkDropdown,
                          PowerDropdown, SystemDropdown, CalendarDropdown,
                          LauncherPanel (NEW)
    buttons/               bar chips: Battery, Bluetooth, Button, Buttons,
                          Clock, Cpu, Logo, Network, Tray, Volume, Workspaces
    components/            shared row/UI bits: BulletDivider, CoreRow,
                          DeviceRow, DiskRow, FormField, PortRow, ProcessRow,
                          Section (has leftContent/rightContent/bottomContent/
                          minHeight slots now, all opt-in), Sparkline
```

## Phase status (the 6 original bar dropdowns + calendar)

All done, real-data-wired, built and screenshot-verified earlier in this
project: **Network, Audio, Bluetooth, Power, System monitor, Calendar +
todo**. Calendar's todos persist in real SQLite via `QtQuick.LocalStorage`
(`~/.local/share/quickshell/QML/OfflineStorage/Databases/*.sqlite`, table
`todos`) — chosen over flat JSON specifically because a future Google
Calendar/ICS sync would want real indexed date-range queries and per-source
sync state; that integration itself is *not* built, just the storage choice
made with room for it. No seed/demo data — starts genuinely empty.

## Launcher feature (the current/newest work, this session)

**Goal**: replace rofi entirely (`coel-main-menu`'s categorized dmenu, plus
`rofi -show drun` for app launching) with an in-process Quickshell
"Spotlight" launcher. Long-term plan (stated by the user, not yet started):
integrate a clipboard manager (real one already exists: `cliphist`, currently
wired to rofi via `$mainMod, V` in `home/hyprland.nix`) and a from-scratch
emoji picker (currently `coel-emoji-picker` = `rofi -modi emoji`) into the
launcher's side/preview panel, which is *why* that panel was deliberately
built to support showing a real image (`previewImage` field) and not just
an icon glyph, from the very first pass.

### Done (this session, phase 1 UI + phase 2 logic)

- Full category browser: launch / panels / toggles / capture / style /
  math / system, chips + fuzzy search across all of them, keyboard nav
  (arrows/tab/enter, category cycling, Escape layers: about-view -> clear
  query -> close), preview panel (icon or image + key/value rows + action
  hint), a real "About this system" page (live hostname/kernel/uptime/
  Hyprland+zsh version/CPU/mem/disk via one combined `sh -c` Process).
- **Real command execution**: `command` items call
  `Quickshell.execDetached(...)` for real and close the launcher after.
- **Real panel-opening**: `panel` items (Network/Bluetooth/Audio/Power/
  System monitor/Calendar) really open that dropdown, via a signal chain
  `LauncherPanel.openPanelRequested(name)` -> `Launcher.openPanelRequested
  (screen, name)` -> `shell.qml` -> `Panel.openPanelRequested(screen,
  name)` -> a `Connections{target:panelScope}` block inside each
  per-screen `PanelWindow` that only reacts if it's *its own* screen.
- **Real toggles, investigated not assumed**:
  - Do Not Disturb: `makoctl mode -t dnd`, state read back via `makoctl
    mode` (never optimistically flipped — same "wait for the next real
    read" rule `SystemDropdown.qml`'s kill action follows). Needed a real
    mako config addition to have any effect: `home/mako.nix` now has
    `"mode=dnd".invisible = 1` — **verified this renders correctly in the
    built mako config output**, but note **mako itself needs to actually
    restart** (via the normal `home-manager switch`/reboot path, not
    anything live-reloadable) to pick it up.
  - Keep awake: real, a `systemd-inhibit --what=idle:sleep ... sleep
    infinity` child process we own the lifecycle of directly (start =
    `running:true`, stop = `running:false` which SIGTERMs it, releasing
    the inhibitor).
  - Night light and Charge limit: **deliberately left non-functional**,
    with an honest message instead of a fake toggle — no compositor
    night-light tool is installed on this machine (checked: no
    hyprsunset/gammastep/wlsunset), and `PowerDropdown.qml`'s own header
    comment already established this hardware has no real charge-limit
    sysfs knob. Don't silently "finish" these without actually installing/
    configuring a real backend first.
  - **Calculator: now real** — ported the mock's `calcEval()` (lines
    ~1060-1280 of "Quickshell Example/Quickshell Bar.dc.html") to
    `sysPanel/Calc.js` (`evaluate(raw, ans)`, a pure function -- the mock's
    version closes over `this.state.menuAns`, ours takes `ans` as a plain
    argument since there's no component state to read). Near-verbatim port,
    same recursive-descent parser/evaluator/pretty-printer: sqrt/cbrt/nth
    root, log/log2/log10/ln with `log_2(x)`/`log2(x)`/`root(3)(27)`
    subscript-or-double-paren forms, full trig+inverse+hyperbolic,
    factorial/gamma/ncr/npr/gcd/lcm, hex/binary literals, named constants
    (pi/tau/e/phi/inf/**ans**), superscript-digit exponents (x²), percent-of
    (`120 + 15%`), `mod`, degree conversion (`sin(30°)`), and the exact/π-
    fraction/scientific-notation/hex/bin result breakdown. Verified by
    running the ported file under Node against all 14 of the mock's own
    "math" category example expressions (`sqrt16`, `root(3)(27)`, `5!`,
    `ans / 2`, etc.) plus a couple of malformed inputs — every result
    matched the mock's expected output byte-for-byte, including `ans`
    correctly carrying over between evaluations.
    `LauncherPanel.qml`'s `fuzzyList()` now calls `Calc.evaluate(raw,
    ansValue)` and, when it returns a result, forces it into the top slot
    exactly like the mock's `menuList()` does (a valid expression always
    wins over a fuzzy text match). Enter on a calc result: `ok` ones
    `Quickshell.execDetached(["wl-copy", c.raw])` (no shell, so no quoting
    concerns) and store `c.value` in a new `ansValue` property for the next
    `ans` reference; failed ones (`c.ok === false`) just surface `c.reason`
    as the footer message. Preview panel now shows the calc-specific
    breakdown (expr/exact-fraction/π-fraction/sci/hex/bin/error/copies rows)
    in place of the generic type/keys/runs rows when the selected item is a
    calc result. The math category's example rows (`fill: true`) are
    unchanged — clicking one still just fills the search box, which now
    actually evaluates.
  - **App search** (the actual rofi-drun replacement): real, via
    `scripts/list-apps.py` (parses real `.desktop` files across XDG data
    dirs, XDG precedence for dedup, drops `NoDisplay`/`Hidden`/non-
    Application entries, strips `Exec` field codes, `shlex`-splits,
    auto-wraps `Terminal=true` entries in `ghostty -e`). 52 real apps
    found on this machine at last check. Spotlight-style on purpose: apps
    only enter the result list while there's a non-empty query — verified
    in `fuzzyList()`, no "applications" category chip exists to browse
    them. Icons resolved for real via `Quickshell.iconPath(...)` (a real
    Quickshell singleton method, not invented) into the preview panel's
    image slot; list rows themselves just use a generic icon (kept simple
    on purpose, not a bug).
  - **Hyprland keybinds repointed**: `$mainMod, space` and `$mainMod
    SHIFT, space` both now run `quickshell ipc call launcher toggle`
    (was `rofi -show drun` / `coel-main-menu` respectively) — **both
    point at the same launcher now since it subsumes both jobs**; flagged
    to the user as a judgment call in case they'd rather they stayed
    distinct. **Confirmed working live** (2026-09-27): the user pressed
    `super+space` for real after a rebuild. A real bug turned up along the
    way (see the ipc-path-flag fix below) and is now fixed and
    build-verified.
  - `rofi.nix`'s own scripts (`coel-main-menu`, `coel-actions-menu`,
    `coel-settings-menu`, etc.) were **left completely untouched** —
    only the *keybinds pointing at them* changed. `coel-main-menu` is
    still referenced by `home/waybar.nix`'s `on-click` if waybar is ever
    still relevant; not investigated whether waybar is still live.

### `super+space` real bug + fix (2026-09-27)

`super+space` still launched old rofi even after a rebuild because the
two ipc-call keybinds in `home/hyprland.nix` had no path/config flag, so
they targeted quickshell's *default* instance
(`~/.config/quickshell/shell.qml`) — but the exec-once above launches
with `-c ~/.nixos/home/quickshell` (intentionally, for hot-reload), a
different config path/instance entirely. Confirmed via `quickshell ipc
--help`: `-c` there means a named XDG config, not a path; `-p`/`--path`
is the actual "path to a config" flag. All ipc-call binds (space,
shift+space, and the new super+V below) now read `quickshell ipc -p
~/.nixos/home/quickshell call launcher <fn>`, verified against the real
generated `hyprland.conf` after a build and confirmed live by the user.

### Emoji picker (real, search-only, done 2026-09-27)

`emojiEntries`, loaded once via a lazy `Component.onCompleted`-style load
on first panel open (static data, not re-fetched every open like DND
state). Real dataset, not invented — vendored from the real `rofi-emoji`
package (`pkgs.rofi-emoji`, MIT, see `scripts/emoji-data.LICENSE`) into
`scripts/emoji-data.txt` (5042 lines, copied byte-for-byte via `cp`, never
retyped) rather than read live from its nix store path, since that path's
hash changes on every nixpkgs update. Matched against name + keywords,
scored/sorted and capped at 20 results — 5042 is too many to ever browse
as a static category (no chip exists for it, same "Spotlight not rofi"
call as app search), so it stays search-only.

Selecting one runs `Quickshell.execDetached(["wl-copy", emojiChar])`
directly — no shell needed since it's a single argv element, and the text
comes from our own vendored file rather than anything external/untrusted.
Preview panel shows the real glyph (via "Noto Color Emoji", already
installed) instead of a generic Phosphor icon when an emoji result is
selected — Phosphor is an icon font, has no emoji glyphs of its own. Two
new Phosphor codepoints added for this (`clipboard`/`clipboard-text`/
`smiley`), verified against the same cached `phosphor-icons/core` source
table as every other codepoint in `Phosphor.js`, not guessed.

**User-confirmed working** (2026-09-27) via real search. One follow-up:
Plasma's own "Emoji Selector" app (`plasma-emojier`, a real installed
KDE app, correctly surfaced by `list-apps.py`) was showing up alongside
these for the same query, which was confusing now that emoji search is
native. Filtered it out specifically in `LauncherPanel.qml`'s app-search
loop (`app.argv[0] === "plasma-emojier"`), **not** via
`home/desktop-entries.nix`'s `hiddenDesktopIds` — that writes
`Hidden=true` to `$XDG_DATA_HOME`, which every spec-compliant consumer
honors (confirmed against that file's own header comment), including
Plasma's own Kickoff/KRunner. Since Plasma stays installed as a fully
independent fallback session with no access to this launcher, hiding it
there would leave Plasma without a working emoji picker. Discussed with
the user, this was their call to make and they agreed with the launcher-
local fix.

### Clipboard tab (real category + live preview, done 2026-09-27)

Originally built search-only like emoji (see git history / earlier
revisions of this doc), but the user asked for a real dedicated,
always-browsable tab instead, plus a live preview showing actual decoded
content — "I think will be the hardest part here" per the user. Also
asked to **remove the `panels` and `style` categories** entirely (not
using them) and to make **`super+V`** open straight to this tab.

- **Category, not search-only**: `clipboardCategoryItems()` maps every
  real `cliphist list` entry (no cap — cliphist's own history size is the
  only limit) into the `clipboard` category. This only works without a
  massive performance hit because the item list rendering was converted
  from a plain `Flickable`+`Column`+`Repeater` (which instantiates *every*
  row up front regardless of scroll position) to a real `ListView` with
  `reuseItems: true`, which only builds delegates near the visible
  viewport. Search still works normally across it too — since it's a real
  category now, the existing generic `categories.forEach` search loop
  covers it for free, no special-cased search injection needed (unlike
  emoji, which still needs its own capped block since it isn't a
  category).
  - **Real bug the user caught immediately: scrolling didn't work.** The
    `rows` computed property used to bake `isSel` into each row object,
    which meant it (and therefore `ListView.model`) got rebuilt into a
    *brand-new array* on every `selIndex` change -- including plain mouse
    hover. Reassigning a ListView's `model` to a new array identity resets
    its scroll position, which fought every scroll attempt (any hover
    during a scroll gesture as rows slid under the cursor snapped it back
    to top). This never showed up with the old `Column`+`Repeater` because
    `Flickable.contentY` there was independent scroll state, untouched by
    `Repeater.model` reassignment -- a ListView doesn't have that
    separation. Fixed by making `rows` never depend on `selIndex` at all
    (only on `list`), and having each delegate read `panelRoot.selIndex`
    directly for its own highlight state instead. Worth remembering for
    any *other* ListView added later in this file: never embed selection
    state in the model data itself.
- **Live preview, the "hardest part"**: selecting a clipboard entry
  (arrow keys or hover) decodes its *real* content immediately, not just
  the mangled/truncated `cliphist list` preview — text keeps its original
  whitespace/newlines (`textFormat: Text.PlainText`, `wrapMode: Text.Wrap`,
  no collapsing), images render as real images. Two dedicated `Process`es
  (`clipTextDecodeProc`/`clipImageDecodeProc`) do this, **deliberately
  serialized**: a new decode never starts while one's already in flight
  for a previous selection. Rapid arrow-key movement would otherwise mean
  two `cliphist decode > <sharedfile>` calls racing to write the *same*
  temp image file, which could interleave into a corrupted image. Instead,
  a process that finishes and finds the selection has moved on
  (`forLine` no longer matches the live selection) just re-checks and
  kicks off a fresh decode for wherever the selection actually is now —
  always converges to the true-latest selection without ever needing
  per-request unique temp files. Image-vs-text is known upfront from
  `cliphist list`'s own marker (`"[[ binary data %s %s %dx%d ]]"`,
  confirmed via `strings` on the real `cliphist` binary, not guessed).
  Copying (Enter/click) still goes through the original
  `copyClipboardEntry()` → stdin-piped `cliphist decode | wl-copy`, separate
  from the preview-decode processes.
- **`super+V` rewired**: was `cliphist list | rofi -dmenu | cliphist
  decode | wl-copy`; now `quickshell ipc -p ~/.nixos/home/quickshell call
  launcher openClipboard` — a new IpcHandler function (alongside `toggle`)
  that resolves the focused screen the same way `toggle` does, then fires
  a new `openCategoryRequested(screen, "clipboard")` signal. Threaded
  through `shell.qml` (`launcherRequestedCategory` property,
  `openLauncherCategory()` function — toggles closed if already open on
  clipboard, otherwise opens/switches to it) down to `LauncherPanel`'s
  `requestedCategory` prop, consumed once in `onPanelOpenChanged` to jump
  `catIndex` to the right category. A plain `toggle()` (space) clears the
  forced category so it doesn't linger and hijack a later space-press.
  **Build-verified** (generated `hyprland.conf` has the right bind) but
  not yet a real keypress test — needs the same rebuild+switch step
  `super+space` needed, since it's a Hyprland-level bind, not something
  QML hot-reload covers.
- **`panels` and `style` categories removed** per explicit request (not
  used). The underlying `openPanelRequested` signal chain (`LauncherPanel`
  → `Launcher.qml` → `shell.qml` → `Panel.qml`'s `Connections` block) was
  **left in place**, just now unreferenced by any category item — flagged
  to the user rather than unilaterally ripped out across 4 files, since
  "remove the tab" and "delete the plumbing" are different asks. Revisit
  if confirmed fully dead.
- **Not yet done**: real image thumbnails specifically in *search results*
  for image-type clipboard entries outside the clipboard tab (e.g. if a
  future search source wants one) — the live preview above covers the
  actual clipboard tab fully now.

## Current git state (uncommitted, staged by Claude per convention)

```
 M "Quickshell Example/Quickshell Bar.dc.html"   <- user's own unstaged edit, leave alone
M  home/hyprland.nix                              <- keybind repoints + ipc -p path fix +
                                                       super+V rewired to openClipboard
M  home/mako.nix                                  <- [mode=dnd] rule
A  home/quickshell/Launcher.qml                   <- new
A  home/quickshell/STATUS.md                      <- this file
A  home/quickshell/scripts/emoji-data.LICENSE     <- new, MIT, from pkgs.rofi-emoji
A  home/quickshell/scripts/emoji-data.txt         <- new, vendored emoji dataset (5042 lines)
A  home/quickshell/scripts/list-apps.py           <- new
M  home/quickshell/shell.qml                      <- launcher wiring + requestedCategory plumbing
A  home/quickshell/sysPanel/Calc.js                <- new, calculator engine
M  home/quickshell/sysPanel/Panel.qml              <- openPanelRequested plumbing (now unreferenced,
                                                       see clipboard-tab section above)
M  home/quickshell/sysPanel/Phosphor.js            <- +40 icon codepoints, +3 this session
                                                       (clipboard/clipboard-text/smiley), all
                                                       verified against real phosphor-icons/core
                                                       source, cached at /tmp/phosphor_icons.ts
                                                       if still there
M  home/quickshell/sysPanel/buttons/Logo.qml       <- emits clicked() instead of exec'ing directly
A  home/quickshell/sysPanel/dropdowns/LauncherPanel.qml  <- the big one -- panels/style categories
                                                       removed, clipboard is a real ListView-backed
                                                       category with a live-decode preview, emoji
                                                       search added
```

Also present in the working tree, **unstaged and not from this work**:
`flake.nix` (whitespace/formatting only) and `flake.lock` (+1 stray
`nixpkgs_6` locked input) both changed mid-session, ~2026-09-27, most
likely from the user's own editor/Nix LSP running concurrently (same
session where the user also hand-edited `shell.qml`'s `Border` binding
live) rather than anything either of us did deliberately. Not staged,
not investigated further — mention it if it looks wrong later.

All of the above builds clean (`nix build` succeeded, last checked this
session, including confirming the generated `hyprland.conf` actually
contains the fixed `ipc -p` keybinds and the new `super+V` bind) and
`qmllint` is clean on every touched file. The user's **live production**
quickshell instance (launched via their own Hyprland session, not a
throwaway dev copy — important distinction learned the hard way this
session, see below) auto-hot-reloads on QML edits, confirmed via `quickshell
ipc -p ~/.nixos/home/quickshell show` listing the new `openClipboard`
target without any relaunch. Nothing here is committed — that's the
user's call, by design.

**Process note for future sessions**: earlier in this session, `pkill -f
"quickshell -c"` (the established dev-instance-cycling pattern from
earlier in the project) was used for routine testing and it killed the
user's actual live panel, since their real session now runs its own
production instance at the same `-c ~/.nixos/home/quickshell` invocation
as any throwaway dev instance — there's no way to tell them apart by
command line alone. Recovered immediately by relaunching, no data lost,
but the practice has stopped: validation from here on is qmllint + `nix
build` + read-only `quickshell ipc ... show` introspection only. Don't
pkill/relaunch quickshell for testing without asking first.

## Immediate next steps (in the order they're likely to come up)

1. **Live-test `super+V` for real** (an actual keypress) after the next
   rebuild+switch — same remaining gap as `super+space` had, now closed
   for that one.
2. Decide whether to retire/repoint `coel-emoji-picker` (`$mainMod,
   period`) now that emoji search is native and Plasma's own entry is
   filtered out of results — same kind of call as the drun/`coel-main-menu`
   repoint earlier, not made unilaterally.
3. Decide whether the now-unreferenced `openPanelRequested` signal chain
   (`LauncherPanel`/`Launcher.qml`/`shell.qml`/`Panel.qml`) should be
   ripped out, or left in case a future "quick-open a panel" entry point
   wants it again.
4. Screenshot-based mock review is **done for now** per the user
   (2026-09-27) — no more mock pages incoming for the launcher work
   already built. Don't proactively ask for more.
5. `Border.qml`'s `bgColor`-as-`borderColor` binding in `shell.qml`: not a
   bug — user confirmed live that the opaque border is intentional. Don't
   "fix" this again.

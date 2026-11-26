# coelOS "flair" handoff

Context from a claude.ai chat where Claude read this repo (all commits) and quizzed me to find out what would make coelOS feel less "complete" and more "wow". Read CLAUDE.md / AGENTS.md / home/quickshell/STATUS.md first; their rules (live hot-reloading Quickshell, never restart it without asking, I switch and commit myself, Nerd Font icon rules) all still apply.

## Diagnosis

coelOS is heavy on capability and correctness (Quickshell replaces bar/launcher/notifs/lock/greeter/polkit/share picker, session hub, grid workspaces + overview, Miracast/Cast, fnlock, screen-ask, settings.toml, tests), but light on atmosphere. It can do almost anything, but it doesn't *notice* anything.

## My answers (design constraints)

- Audience: **me, every day**: small daily delights, not screenshot bait.
- Flattest moment: the **idle desktop** (empty workspace + widgets is what I usually see when idle).
- **One Dark is identity.** No wallpaper-derived or time-shifting palettes. Wow comes from behavior, not color.
- Open to: **tactile/mechanical UI sounds**, **expressive but precise & snappy motion** (no overshoot/bounce), **ambient reactivity**. Not interested in blur.
- "Alive" flavor: **it knows**: contextual info surfaces by itself.
- Where it surfaces: a **morphing pill in the bar** (Dynamic-Island style).
- Interruption: **a mix by urgency**: ambient for minor, glanceable for normal, allowed to interrupt for big stuff (print failed, class starting, battery critical).
- Things it should know about: **Bambu printer progress**, **schedule/time** (next class/event), **music now playing**. Also phone via **KDE Connect** (still enabled in modules/kdeconnect.nix).
- Signature moments I want: **seamless boot -> greeter -> desktop** and a **time-of-day greeting**.
- **Modes: yes, automatic** (Class / Deep work / Printing / Gaming etc.), inferred, with manual override.
- I use coelOS for coding, CAD/robotics/3D printing, school, media & games; even keyboard/touchpad mix.

## Plan (build order)

1. **Live-activity pill in the bar** (start here; everything else plugs into it). Generalize `sysPanel/buttons/AssistantStatus.qml` (already a working/done/fail bubble driven by IPC) into an activity system: one backend Item per source, like `launcher/backends/`. Sources: Bambu (LAN MQTT with the access code: progress, layer, ETA, finished/failed; later a camera snapshot on finish), Mpris, next event from gcal-sync's data, KDE Connect (calls, phone notifs, low phone battery), Pomodoro, casting, screen recording, VPN connecting, screen-ask. Three tiers: ambient (dot/compact chip), glance (expand a few seconds, collapse), interrupt (expand and stay + sound). Morphs ~200 ms, critically damped, no overshoot. Respect `Globals.eyeCandyOff`. **First milestone: the pill framework + Bambu as the first source.**
2. **Automatic modes**: small daemon in the style of `scripts/coel-hub.py`; infers mode from calendar event names, Hyprland socket2 events (focused app class, fullscreen game), printer state, time. Modes declared in settings.toml (`[modes.class]`, etc.) controlling DND, widget set, pill priority, sound level. Manual override as a launcher action. Pushes mode to Quickshell over IPC.
3. **Context-aware idle desktop**: widgets rearrange per mode/context (printing -> print card is the hero; before class -> countdown + kanban column; music + idle -> album art).
4. **Time-of-day greeting** on first unlock of the day (session hub knows): "Good morning, Joel - 2 classes, print done 11:40, 64° clear", then each line animates into its widget's position.
5. **Seamless boot -> desktop**: pixel-matched logo positions Plymouth -> greeter; on login the auth card collapses into the bar's `Logo.qml` while widgets stagger in. Risk: VT1 -> VT7 switch flash; likely needs the session Quickshell to start with an overlay matching the greeter's last frame, then animate it away.
6. **Tactile sound pack** (~8 short samples via QtMultimedia SoundEffect): pitch-rising volume ticks, toggle clack, launcher tick, lock thunk/unlock, one tonal chime reserved for print done. Mode-aware (silent in Class), off with eyeCandyOff. Plus crisp Hyprland window open/close animations and dropdowns that grow from their bar button.

Start with step 1. Read the relevant mockups in `~/.nixos/example/*.dc.html` and follow the repo's "hardcoded UI first, real logic second" pattern. Propose the pill's design before wiring real data.

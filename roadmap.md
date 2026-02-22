# The Polish Roadmap

Archinstall → Run Install Script → Login to Hyprland

This document is a **step-by-step roadmap** for turning a working Arch + Hyprland setup into a _polished, complete-feeling operating system_.

Work **top to bottom**.  
Do **not** skip ahead.  
Each phase builds on the previous one.

---

## Phase 1 — Does the machine behave correctly?

**Focus:** Hardware, laptop behavior, and basic expectations

**Goal:** The machine behaves like a normal laptop or desktop without surprises.

### Checklist

- [x] Volume up/down works
- [x] Volume mute works
- [x] Brightness up/down works
- [x] Media play/pause works
- [x] Media next works
- [x] Media previous works
- [ ] Play/Pause indicators styled
- [x] Touchpad tap-to-click works
- [x] Touchpad scrolling feels correct
- [x] Touchpad disable-while-typing works
- [ ] External mouse behaves correctly
- [x] Laptop lid close suspends the system
- [x] Power button performs expected action
- [x] Resume from sleep works reliably

If this phase is incomplete, the system will always feel broken.

---

## Phase 2 — Can I lock, sleep, and walk away?

**Focus:** Security and idle behavior

**Goal:** The system protects itself when unattended.

### Checklist

- [x] Lock screen works when launched manually
- [x] Screen locks automatically after inactivity
- [x] Screen locks before suspend
- [x] Screen locks when lid is closed
- [x] Screen blanks before locking
- [x] Resume from suspend returns to a locked screen
- [x] No freezes or black screens after resume

This phase separates a usable system from an unsafe one.

---

## Phase 3 — Do I get feedback when I press keys?

**Focus:** On-screen feedback and notifications

**Goal:** The system visibly responds to user actions.

### Checklist

- [x] Notifications appear reliably
- [x] Volume changes show a popup
- [x] Brightness changes show a popup
- [ ] Media key presses show feedback
- [x] Mute states are clearly visible
- [ ] No duplicate popups
- [ ] Popups appear on the active monitor

This is where the system starts to feel alive.

---

## Phase 4 — Does the desktop feel stable?

**Focus:** Reliability and session consistency

**Goal:** The desktop behaves the same way every login.

### Checklist

- [x] Waybar loads on every login
- [x] Waybar does not randomly crash
- [x] System tray works correctly
- [x] Network status is visible
- [x] Bluetooth status is visible
- [x] Battery indicator is accurate
- [x] Clock shows the correct time
- [x] Tooltips render correctly

If this phase fails, the system feels fragile.

---

## Phase 5 — Do apps behave like normal apps?

**Focus:** Wayland integration and portals

**Goal:** Applications behave as users expect.

### Checklist

- [ ] File manager opens correctly
- [ ] File picker works in applications
- [x] Screenshot tool works
- [x] Clipboard copy and paste works
- [ ] Drag and drop works
- [ ] Electron apps behave normally
- [ ] Flatpak apps behave normally

Most of these problems are invisible until they break.

---

## Phase 6 — Does it handle power correctly?

**Focus:** Battery life and thermals

**Goal:** The system is efficient, cool, and predictable.

### Checklist

- [x] Suspend works reliably
- [x] Resume works reliably
- [ ] Power profiles switch correctly
- [ ] CPU frequency scaling works
- [ ] Fan behavior is sane
- [x] Battery percentage reporting is accurate
- [ ] Battery drain during sleep is minimal

This phase determines whether the system is usable on the go.

---

## Phase 7 — Does it feel visually consistent?

**Focus:** Theming and appearance cohesion

**Goal:** Everything looks intentional and unified.

### Checklist

- [ ] GTK theme applied everywhere
- [ ] Icon theme consistent
- [x] Cursor theme consistent
- [ ] Fonts consistent across applications
- [x] Terminal theme matches desktop
- [x] Lock screen matches desktop theme
- [x] Login screen matches desktop theme

This is where the system starts to feel polished.

---

## Phase 8 — Is boot → login → desktop smooth?

**Focus:** Experience polish (optional but powerful)

**Goal:** A clean, quiet, and fast startup experience.

### Checklist

- [ ] Boot splash displays correctly
- [ ] No kernel spam during boot
- [ ] Encryption prompt is clean
- [ ] Login screen loads quickly
- [ ] Desktop is ready immediately after login
- [ ] No error popups on startup

This is where a system feels professional.

---

## Phase 9 — Can I break it and recover?

**Focus:** Safety and recovery

**Goal:** You can experiment without fear.

### Checklist

- [ ] System snapshots enabled
- [ ] Rollback works
- [ ] Emergency TTY accessible
- [ ] Logs are accessible
- [ ] System can be repaired without reinstalling

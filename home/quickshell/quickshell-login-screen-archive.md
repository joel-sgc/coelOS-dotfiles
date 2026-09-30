# Quickshell Login Screen on NixOS (greetd + Quickshell) — archived, pre-implementation draft

**Archived 2026-09-30.** This was written *before* the real greeter/lock
screen existed, as a design sketch. The actual implementation diverged
significantly and none of the file paths or component names below are
real: the module is `modules/greeter.nix` (not `modules/qs-greeter.nix`),
there's no `quickshell/theme/` directory, no `Theme.qml`/`Avatar.qml`/
`UserPicker.qml`/`SessionPicker.qml`/`LockBackend.qml`. For the real,
verified architecture and file layout, see `home/quickshell/STATUS.md`'s
"Lock screen + greetd login screen" section instead. Kept here only for
whatever design rationale still applies, not as a reference for real paths.

A design and implementation guide for a login screen written in Quickshell/QML, running under greetd on NixOS, able to start both **Hyprland** and **KDE Plasma (Wayland)** sessions. It is built so the login screen and the lock screen share one set of QML components and look the same.

> Target versions: Quickshell ≥ 0.2 (for `import qs.*` module imports), greetd 0.10.x, NixOS 25.05 or newer. Check option names against your channel with `man configuration.nix` or search.nixos.org, since module options occasionally move.

---

## 1. Goals

- One visual design, one codebase: the greeter and the lock screen import the same `theme/` components.
- No SDDM. greetd handles authentication and session startup, and Quickshell only draws the UI.
- Both Hyprland and Plasma appear as selectable sessions, discovered from the system's session files rather than hard-coded.
- Everything is declared in Nix: the greeter config, fonts, users list and session list are built into the Nix store and are read-only at runtime.
- The greeter can be developed and previewed in a normal window, without logging out.

---

## 2. Architecture

```
            boot
              │
              ▼
   ┌──────────────────────┐      runs as root
   │   greetd daemon      │◄──── PAM (/etc/pam.d/greetd)
   └─────────┬────────────┘
             │ starts greeter session (user: greeter)
             ▼
   ┌──────────────────────┐
   │  cage (kiosk Wayland │      runs as unprivileged "greeter"
   │  compositor)         │
   │   └─ quickshell -p   │
   │      /nix/store/…    │
   │      greeter config  │
   └─────────┬────────────┘
             │ IPC over $GREETD_SOCK:
             │ create_session → auth prompts → start_session
             ▼
   greetd starts the chosen session as the user
   (Hyprland  or  startplasma-wayland)
```

### Who does what

| Component | Runs as | Responsibility |
|---|---|---|
| **greetd** | root | Owns the VT, runs PAM, starts the user session. The only privileged piece. |
| **cage** | greeter | A minimal Wayland kiosk compositor. It shows one fullscreen app and exits when that app exits. |
| **Quickshell greeter** | greeter | Draws the UI and forwards username, password and session choice to greetd over its socket. |
| **Shared `theme/`** | n/a | Background, clock, avatar, auth card and power buttons, used by both greeter and lock screen. |
| **Nix module** | build time | Packages the QML, generates `users.json` and `sessions.json`, configures greetd, fonts and PAM. |

The greeter never has root access and never starts a session itself. It asks greetd to start one after greetd has authenticated the user.

---

## 3. Choosing the greeter compositor

The greeter needs a Wayland compositor to draw into. There are two good options.

| | **cage** (recommended to start) | **Hyprland (greeter-only config)** |
|---|---|---|
| Setup | One command line | A separate small `hyprland.conf` |
| Multi-monitor | Mirrors or extends a single window; no per-monitor layout | Full per-monitor layout, same `monitor=` lines as your session |
| Window type in QML | `FloatingWindow` (cage fullscreens it) | `PanelWindow` per screen via `Variants` (layer-shell) |
| Exit behaviour | Exits automatically when Quickshell exits | Needs `hyprctl dispatch exit` after Quickshell exits |
| Scaling | `WLR_*` / output defaults; set scale via env or accept 1× | Same `monitor=…,scale` as your real session, which gives an exact visual match |

Start with **cage**. If you have several monitors, or the greeter's scaling doesn't match your session, switch to the Hyprland variant in [section 8.5](#85-optional-hyprland-as-the-greeter-compositor). The QML only changes in the root window type.

---

## 4. Repository layout

Keep the theme in one place and have both configs reference it.

```
nixos/
├─ modules/
│  └─ qs-greeter.nix          # NixOS module (section 8)
└─ quickshell/
   ├─ theme/                  # SHARED: used by greeter AND lock screen
   │  ├─ Theme.qml            # singleton: colours, fonts, sizes, wallpaper path
   │  ├─ Background.qml       # wallpaper + blur + dim
   │  ├─ Clock.qml
   │  ├─ Avatar.qml
   │  ├─ AuthCard.qml         # password field + message line; talks to a "backend"
   │  └─ PowerButtons.qml
   ├─ greeter/
   │  ├─ shell.qml            # greeter entry point
   │  ├─ GreeterBackend.qml   # singleton: greetd state machine (+ mock mode)
   │  ├─ UserPicker.qml
   │  ├─ SessionPicker.qml
   │  └─ assets/              # avatars, wallpaper (copied into the store)
   └─ lock/
      ├─ shell.qml            # lock entry point (WlSessionLock)
      └─ LockBackend.qml      # singleton: PamContext wrapper
```

### The key rule: components take a backend, not an auth system

`AuthCard.qml` never imports `Quickshell.Services.Greetd` or `Quickshell.Services.Pam`. It talks to a `backend` object that exposes the same small interface in both cases:

```
backend.busy      : bool     // auth in progress
backend.message   : string   // info or error text to display
backend.isError   : bool
backend.submit(password)     // start or continue authentication
signal backend.failed()      // shake / clear the field
```

`GreeterBackend` implements this with greetd, and `LockBackend` implements it with PAM. Because the visuals are identical code, the two screens can't drift apart.

---

## 5. Login flow (sequence)

1. greetd starts `cage → quickshell` as the `greeter` user.
2. Quickshell loads `users.json` and `sessions.json` (generated by Nix) and the last-used user and session from `/var/lib/qs-greeter/state.json`.
3. The user picks an account and session and types a password.
4. `GreeterBackend.submit()` calls `Greetd.createSession(user)`.
5. greetd runs PAM and sends one or more `authMessage` signals.
   - For a secret prompt (`responseRequired && !echoResponse`), the backend replies with the typed password via `Greetd.respond()`.
   - Any further prompts (OTP code, "touch the fingerprint sensor") are shown in the UI and answered interactively.
6. On success greetd emits `readyToLaunch`. The backend saves the state file, runs a short fade (< 300 ms), then calls `Greetd.launch(command, environment)`.
7. Quickshell exits, cage exits, and greetd starts the session as that user.
8. On failure, `authFailure(message)` fires and the session is torn down by greetd. The UI shows the message and clears the field.

> greetd expects the greeter to exit promptly after launch. Do any exit animation **before** calling `launch()`, and keep it short.

---

## 6. QML implementation

### 6.1 `theme/Theme.qml`

```qml
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // Replace with the values from your designs.
    readonly property color bg:        "#11111b"
    readonly property color surface:   Qt.rgba(0.12, 0.12, 0.18, 0.55)
    readonly property color text:      "#cdd6f4"
    readonly property color subtext:   "#a6adc8"
    readonly property color accent:    "#89b4fa"
    readonly property color error:     "#f38ba8"

    readonly property string fontFamily: "Inter"        // must be in fonts.packages
    readonly property string clockFont:  "Inter Display"

    readonly property int radius: 18
    readonly property real blurAmount: 0.8
    readonly property real dim: 0.35

    // Resolved relative to the config root, so it works from the Nix store.
    readonly property url wallpaper: Qt.resolvedUrl("../greeter/assets/wallpaper.jpg")
}
```

The lock screen uses this same file, so the wallpaper path must be readable by the greeter user too, which is why it lives in the store rather than in `~`.

### 6.2 `theme/Background.qml`

```qml
import QtQuick
import QtQuick.Effects
import qs.theme

Item {
    anchors.fill: parent

    Image {
        id: wall
        anchors.fill: parent
        source: Theme.wallpaper
        fillMode: Image.PreserveAspectCrop
        visible: false          // drawn through the effect below
        asynchronous: true
    }

    // Blur is done in Qt, not by the compositor, so it's identical under
    // cage, Hyprland and KWin.
    MultiEffect {
        anchors.fill: wall
        source: wall
        blurEnabled: true
        blur: Theme.blurAmount
        blurMax: 64
        brightness: -Theme.dim
    }
}
```

### 6.3 `theme/AuthCard.qml`

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.theme

Rectangle {
    id: card
    required property var backend     // GreeterBackend or LockBackend
    property string heading: ""

    implicitWidth: 380
    implicitHeight: col.implicitHeight + 48
    radius: Theme.radius
    color: Theme.surface

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        Text {
            text: card.heading
            visible: text.length > 0
            color: Theme.text
            font { family: Theme.fontFamily; pixelSize: 20; weight: Font.DemiBold }
            Layout.alignment: Qt.AlignHCenter
        }

        TextField {
            id: pw
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: card.backend.promptText || "Password"
            enabled: !card.backend.busy
            focus: true
            font.family: Theme.fontFamily
            color: Theme.text
            onAccepted: card.backend.submit(text)
        }

        Text {
            text: card.backend.message
            visible: text.length > 0
            color: card.backend.isError ? Theme.error : Theme.subtext
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // Clear the field and shake on failure.
    Connections {
        target: card.backend
        function onFailed() { pw.text = ""; shake.restart(); pw.forceActiveFocus() }
    }

    SequentialAnimation {
        id: shake
        loops: 2
        NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; to: 10; duration: 40 }
        NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; to: -10; duration: 40 }
        NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
    }
}
```

`Clock.qml`, `Avatar.qml` and `PowerButtons.qml` follow the same pattern: pure visuals, parameters in, no auth logic.

### 6.4 `greeter/GreeterBackend.qml`

This is the greetd state machine. It also has a **mock mode** that turns on automatically when greetd isn't present, so you can run the greeter in a window while designing it.

```qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

Singleton {
    id: root

    // ---- interface consumed by theme/AuthCard.qml ----
    property bool busy: false
    property string message: ""
    property bool isError: false
    property string promptText: ""
    signal failed()

    // ---- greeter-specific state ----
    property string selectedUser: ""
    property var selectedSession: null        // entry from sessions.json
    readonly property bool mock: !Greetd.available

    property var users: []
    property var sessions: []

    // Password is held only for the first secret prompt, then dropped.
    property var _pendingSecret: null
    // Set when PAM asks a follow-up question (OTP etc.)
    property bool _interactivePrompt: false

    // ---------- data files built by Nix ----------
    FileView {
        path: Qt.resolvedUrl("users.json")
        onLoaded: root.users = JSON.parse(text())
    }
    FileView {
        path: Qt.resolvedUrl("sessions.json")
        onLoaded: {
            root.sessions = JSON.parse(text())
            if (!root.selectedSession && root.sessions.length)
                root.selectedSession = root.sessions[0]
        }
    }

    // ---------- remembered user/session (writable state dir) ----------
    FileView {
        id: stateFile
        path: "/var/lib/qs-greeter/state.json"
        watchChanges: false
        onLoaded: {
            try {
                const s = JSON.parse(text())
                root.selectedUser = s.user ?? root.selectedUser
                const match = root.sessions.find(x => x.id === s.session)
                if (match) root.selectedSession = match
            } catch (e) { /* first boot: no state yet */ }
        }
    }

    function saveState() {
        if (mock) return
        stateFile.setText(JSON.stringify({
            user: selectedUser,
            session: selectedSession ? selectedSession.id : ""
        }))
    }

    // ---------- public API ----------
    function submit(input) {
        if (busy && !_interactivePrompt) return
        isError = false
        message = ""

        if (_interactivePrompt) {                 // answering OTP/2nd prompt
            _interactivePrompt = false
            busy = true
            mock ? mockRespond(input) : Greetd.respond(input)
            return
        }

        busy = true
        _pendingSecret = input
        mock ? mockCreate() : Greetd.createSession(selectedUser)
    }

    function cancel() {
        _pendingSecret = null
        _interactivePrompt = false
        busy = false
        if (!mock) Greetd.cancelSession()
    }

    // ---------- greetd events ----------
    Connections {
        target: Greetd
        enabled: !root.mock

        function onAuthMessage(msg, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (!echoResponse && root._pendingSecret !== null) {
                    // First secret prompt: send what the user already typed.
                    Greetd.respond(root._pendingSecret)
                    root._pendingSecret = null
                } else {
                    // Follow-up prompt (OTP, second factor, etc.)
                    root.promptText = msg
                    root._interactivePrompt = true
                    root.busy = false
                }
            } else {
                // Informational or recoverable error, e.g. fingerprint retry.
                root.message = msg
                root.isError = error
            }
        }

        function onAuthFailure(msg) {
            root._pendingSecret = null
            root._interactivePrompt = false
            root.promptText = ""
            root.busy = false
            root.isError = true
            root.message = msg || "Authentication failed"
            root.failed()
        }

        function onError(err) {
            root._pendingSecret = null
            root.busy = false
            root.isError = true
            root.message = err
            root.failed()
        }

        function onReadyToLaunch() {
            root.saveState()
            root.launchRequested()     // shell.qml fades out, then calls doLaunch()
        }
    }

    signal launchRequested()

    function doLaunch() {
        const s = selectedSession
        const cmd = s.exec.trim().split(/\s+/)
        const desktops = s.desktopNames || s.id
        const env = [
            "XDG_SESSION_TYPE=wayland",
            "XDG_SESSION_DESKTOP=" + s.id,
            "XDG_CURRENT_DESKTOP=" + desktops
        ]
        if (mock) { console.log("MOCK launch:", cmd, env); Qt.quit(); return }
        Greetd.launch(cmd, env)          // Quickshell exits after greetd acks
    }

    // ---------- mock backend for windowed development ----------
    Timer { id: mockTimer; interval: 600; property var cb; onTriggered: cb() }
    function mockCreate() {
        mockTimer.cb = () => {
            if (root._pendingSecret === "test") { root._pendingSecret = null; root.onMockReady() }
            else { root._pendingSecret = null; root.busy = false; root.isError = true
                   root.message = "Wrong password (mock: use 'test')"; root.failed() }
        }
        mockTimer.restart()
    }
    function mockRespond(_) { mockTimer.cb = () => onMockReady(); mockTimer.restart() }
    function onMockReady() { busy = false; launchRequested() }
}
```

Notes on the auth logic:

- The password is kept only until the first secret prompt and then set to `null`. It is never written anywhere.
- Multi-step PAM stacks (fingerprint via `pam_fprintd`, OTP, `pam_u2f`) work because follow-up prompts switch the card into interactive mode using `promptText`.
- Recoverable errors, such as a fingerprint misread, arrive as `authMessage` with `error = true`. Final failures, such as a bad password, arrive as `authFailure`. This matches the Quickshell docs.

### 6.5 `greeter/shell.qml` (cage variant)

```qml
//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.theme
import qs.greeter

ShellRoot {
    FloatingWindow {          // cage fullscreens its only toplevel
        id: win
        visible: true
        color: Theme.bg

        Item {
            id: content
            anchors.fill: parent
            opacity: 1

            Background {}

            Clock {
                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: parent.height * 0.12 }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 18

                UserPicker {
                    users: GreeterBackend.users
                    current: GreeterBackend.selectedUser
                    onPicked: name => GreeterBackend.selectedUser = name
                    Layout.alignment: Qt.AlignHCenter
                }

                AuthCard {
                    backend: GreeterBackend
                    heading: GreeterBackend.selectedUser
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            RowLayout {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 24 }
                SessionPicker {
                    sessions: GreeterBackend.sessions
                    current: GreeterBackend.selectedSession
                    onPicked: s => GreeterBackend.selectedSession = s
                }
                Item { Layout.fillWidth: true }
                PowerButtons {
                    onPoweroff: power.exec(["systemctl", "poweroff"])
                    onReboot:   power.exec(["systemctl", "reboot"])
                    onSuspend:  power.exec(["systemctl", "suspend"])
                }
            }
        }

        NumberAnimation {
            id: fadeOut
            target: content; property: "opacity"; to: 0; duration: 220
            onFinished: GreeterBackend.doLaunch()
        }

        Connections {
            target: GreeterBackend
            function onLaunchRequested() { fadeOut.start() }
        }
    }

    Process { id: power }
}
```

Power actions work because logind lets the active local session power off or reboot the machine without a password, and the greeter's session is the active one on the seat.

### 6.6 Previewing the greeter in a window

From your normal session:

```bash
quickshell -p ~/nixos/quickshell/greeter
```

`GREETD_SOCK` isn't set there, so `Greetd.available` is false and mock mode turns on. The password `test` "logs in" and prints the launch command. Put a temporary `users.json` and `sessions.json` next to `shell.qml` for this, or symlink the Nix-built ones from `/etc/qs-greeter`.

---

## 7. How the lock screen reuses this

The lock entry point swaps only the window type and backend:

```qml
// lock/shell.qml (sketch)
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.lock

ShellRoot {
    WlSessionLock {
        id: lock
        locked: true
        WlSessionLockSurface {
            Background {}
            Clock { /* same props as greeter */ }
            AuthCard { anchors.centerIn: parent; backend: LockBackend; heading: LockBackend.user }
        }
    }
    Connections { target: LockBackend; function onUnlocked() { lock.locked = false; Qt.quit() } }
}
```

`LockBackend` wraps `PamContext` and exposes the same `busy / message / isError / promptText / submit() / failed()` interface. The only visual differences you'll have are the ones you choose, such as hiding the user and session pickers on the lock screen.

For Plasma, the Look-and-Feel `LockScreen.qml` can import the same components through a thin adapter over Plasma's authenticator. That's covered separately.

---

## 8. NixOS module

### 8.1 `modules/qs-greeter.nix`

```nix
{ config, lib, pkgs, ... }:

let
  src = ../quickshell;

  # Users shown in the greeter: normal (human) accounts only.
  usersJson = pkgs.writeText "qs-greeter-users.json" (builtins.toJSON (
    lib.mapAttrsToList (name: u: {
      inherit name;
      displayName = if (u.description or "") != "" then u.description else name;
    }) (lib.filterAttrs (_: u: u.isNormalUser) config.users.users)
  ));

  # Sessions discovered from the system's wayland-sessions .desktop files,
  # so Hyprland and Plasma entries are always correct for the installed versions.
  sessionsJson = pkgs.runCommand "qs-greeter-sessions.json"
    { nativeBuildInputs = [ pkgs.jq ]; } ''
      dir=${config.services.displayManager.sessionData.desktops}/share/wayland-sessions
      for f in "$dir"/*.desktop; do
        [ -e "$f" ] || continue
        id=$(basename "$f" .desktop)
        name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
        exec=$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | sed -E 's/ ?%[a-zA-Z]//g')
        desk=$(grep -m1 '^DesktopNames=' "$f" | cut -d= -f2- | tr ';' ':' | sed 's/:$//' || true)
        jq -n --arg id "$id" --arg n "$name" --arg e "$exec" --arg d "$desk" \
          '{id:$id, name:$n, exec:$e, desktopNames:$d}'
      done | jq -s . > $out
    '';

  # The complete, read-only greeter config in the Nix store.
  greeterConfig = pkgs.runCommand "qs-greeter-config" { } ''
    mkdir -p $out
    cp -r ${src}/greeter $out/greeter
    cp -r ${src}/theme   $out/theme
    chmod -R u+w $out
    # shell.qml at the config root so `import qs.theme` / `qs.greeter` resolve
    mv $out/greeter/shell.qml $out/shell.qml
    cp ${usersJson}    $out/greeter/users.json
    cp ${sessionsJson} $out/greeter/sessions.json
  '';

  greeterLauncher = pkgs.writeShellScript "qs-greeter" ''
    export XKB_DEFAULT_LAYOUT=${config.services.xserver.xkb.layout}
    export XCURSOR_THEME=Adwaita
    export XCURSOR_SIZE=24
    export QT_QPA_PLATFORM=wayland
    export QT_QUICK_CONTROLS_STYLE=Basic
    exec ${pkgs.cage}/bin/cage -s -d -- \
      ${pkgs.quickshell}/bin/quickshell -p ${greeterConfig}
  '';
in
{
  # --- sessions ---------------------------------------------------------
  programs.hyprland.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = false;   # greetd replaces it

  # --- greetd -----------------------------------------------------------
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${greeterLauncher}";
      user = "greeter";
    };
  };

  # Keep boot/systemd messages from drawing over the greeter's VT.
  systemd.services.greetd.serviceConfig = {
    Type = "idle";
    StandardInput = "tty";
    StandardOutput = "tty";
    StandardError = "journal";
    TTYReset = true;
    TTYVHangup = true;
    TTYVTDisallocate = true;
  };

  # Writable state for "remember last user/session" only.
  systemd.tmpfiles.rules = [
    "d /var/lib/qs-greeter 0755 greeter greeter -"
  ];

  # --- fonts: must be system-wide, the greeter has no ~/.local/share/fonts --
  fonts.packages = with pkgs; [ inter nerd-fonts.jetbrains-mono ];

  # --- keyrings unlocked by the login password --------------------------
  security.pam.services.greetd = {
    kwallet.enable = true;          # Plasma: KWallet (check option name on your channel)
    enableGnomeKeyring = true;      # Hyprland apps using the Secret Service
  };

  # Handy for development: exposes the built config at a stable path.
  environment.etc."qs-greeter".source = greeterConfig;

  environment.systemPackages = [ pkgs.quickshell ];
}
```

Import it from `configuration.nix` (or your flake's module list):

```nix
imports = [ ./modules/qs-greeter.nix ];
```

### 8.2 Why the data comes from Nix

- **Users** come from `config.users.users`, so the greeter never needs to read `/etc/passwd` or anyone's home directory.
- **Sessions** come from the actual `.desktop` files NixOS installs. If Hyprland's launch command changes, or you enable UWSM (`programs.hyprland.withUWSM`), the greeter picks up the new `Exec=` automatically.
- **Avatars** should go in `greeter/assets/<username>.png`, because the greeter user can't read `~/.face`.

### 8.3 Environment for the launched session

`doLaunch()` passes `XDG_SESSION_TYPE`, `XDG_SESSION_DESKTOP` and `XDG_CURRENT_DESKTOP`. greetd also sources `/etc/profile` before starting the command (its `source_profile` default), so NixOS's normal environment is set up as it would be from a TTY login. `startplasma-wayland` and Hyprland both handle the rest of their own startup.

### 8.4 Auto-login (optional)

To skip the greeter on boot but still have it after logout:

```nix
services.greetd.settings.initial_session = {
  command = "Hyprland";   # or the Exec= from sessions.json
  user = "yourname";
};
```

### 8.5 Optional: Hyprland as the greeter compositor

Use this for multiple monitors or exact scaling parity with your session.

```nix
greeterHyprConf = pkgs.writeText "greeter-hyprland.conf" ''
  # Copy the monitor= lines from your real Hyprland config
  monitor = , preferred, auto, 1

  misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
  }
  animations { enabled = false }
  input { kb_layout = ${config.services.xserver.xkb.layout} }

  exec-once = ${pkgs.quickshell}/bin/quickshell -p ${greeterConfig}; ${pkgs.hyprland}/bin/hyprctl dispatch exit
'';

services.greetd.settings.default_session.command =
  "${pkgs.hyprland}/bin/Hyprland --config ${greeterHyprConf}";
```

In `shell.qml`, replace the single `FloatingWindow` with:

```qml
Variants {
    model: Quickshell.screens
    PanelWindow {
        required property var modelData
        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        // Put the full UI on the primary screen and only Background on the others.
    }
}
```

Hyprland may warn about writing cache files as the `greeter` user. Setting `XDG_CACHE_HOME=/var/lib/qs-greeter/cache` in the launcher silences that.

---

## 9. Security checklist

- [ ] The greeter config is built into the **Nix store** and served from `/etc`. Your user can't modify it, so a compromised user account can't turn the login screen into a password logger for other accounts.
- [ ] The only writable greeter path is `/var/lib/qs-greeter`, and it only stores the last username and session ID.
- [ ] The password lives in QML memory only until the first PAM prompt and is set to `null` after. Nothing logs it; avoid `console.log` in the auth path.
- [ ] The `greeter` user has no login shell (the NixOS default) and no extra groups.
- [ ] The only `Process` calls in the greeter are `systemctl poweroff|reboot|suspend`.
- [ ] No `IpcHandler` in the greeter config, so nothing else can drive it.
- [ ] Optionally add brute-force protection with `pam_faillock` on the `greetd` PAM service.
- [ ] Keep another VT available (`Ctrl+Alt+F2`) as a fallback login.

---

## 10. Rollout plan

1. **Design in a window.** Run `quickshell -p …/greeter` in mock mode until it matches your designs.
2. **Test in a VM.** Run `nixos-rebuild build-vm` with the module enabled and log into both Hyprland and Plasma in the VM.
3. **Test on real hardware without committing.** Run `sudo nixos-rebuild test`. This activates greetd now but isn't the boot default, so a reboot returns you to the previous generation if something breaks.
4. **Switch.** Run `sudo nixos-rebuild switch`. Older generations stay in the boot menu as a fallback.
5. **Build the lock screen** from the same `theme/`.

---

## 11. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Black screen, then back to the console | cage or Quickshell crashed | `journalctl -b -u greetd`; run the launcher script by hand from a TTY as a test |
| Wrong or fallback fonts | Fonts are only installed per-user | Add them to `fonts.packages` |
| Greeter looks larger or smaller than the lock screen | Different output scale | Use the Hyprland greeter compositor with the same `monitor=` lines |
| "Session list empty" | `sessions.json` is empty | `cat /etc/qs-greeter/greeter/sessions.json`; check the sessions are enabled |
| Login succeeds but you're returned to the greeter | Session command failed | Check `Exec=` in `sessions.json`; see the session's own journal |
| Greeter restarts right after login | `launch()` was called too late | Keep the fade before `launch()` short |
| KWallet or keyring still asks for a password | PAM integration missing | Check the `security.pam.services.greetd` options |
| `import qs.theme` fails | Quickshell older than 0.2, or `shell.qml` not at config root | Update Quickshell; keep `shell.qml` at the root of the built config |

---

## 12. References

- Quickshell `Greetd` API: https://quickshell.org/docs/types/Quickshell.Services.Greetd/Greetd/
- Quickshell `WlSessionLock`: https://quickshell.org/docs/types/Quickshell.Wayland/WlSessionLock/
- Quickshell `PamContext`: https://quickshell.org/docs/types/Quickshell.Services.Pam/PamContext/
- greetd: https://sr.ht/~kennylevinsen/greetd/
- cage: https://github.com/cage-kiosk/cage
- NixOS options search (greetd, pam, displayManager): https://search.nixos.org/options

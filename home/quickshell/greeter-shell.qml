import Quickshell

import "./greeter"

// ===== GREETER TEST HARNESS =====
// Windowed dev-preview entry point -- launch with
// `quickshell -p ~/.nixos/home/quickshell/greeter-shell.qml`. Outside a
// real greetd session, Quickshell.Services.Greetd.available is false, so
// GreeterBackend.qml auto-switches to its mock mode (demo users/sessions,
// "test" as the accepted password) -- safe to run anytime, same as
// lock-shell.qml is for the lock screen. Not wired into any real greetd
// config yet (that's the NixOS module, a later phase).
ShellRoot {
  Greeter {}
}

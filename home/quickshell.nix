{ pkgs, ... }:

let
  phosphorFont = import ./quickshell-phosphor-font.nix { inherit pkgs; };
in
{
  # QtQuick/QML-based desktop shell toolkit. User-facing desktop tooling
  # (same category as waybar), not a system service, so it belongs here
  # rather than configuration.nix's environment.systemPackages -- moved
  # from there.
  #
  # ./quickshell/shell.qml is the actual config (a waybar-style top panel
  # -- see sysPanel/); this wires the whole directory to
  # ~/.config/quickshell, quickshell's default config search path, so
  # `quickshell` picks it up with no -p/-c flag needed. Icon glyphs used to
  # need a Nix-time text-substitution pass here (a @icon:<name>@ ->
  # codepoint replace, same idea as home/rofi.nix's withIcons) because they
  # were plain string literals; sysPanel/Phosphor.js resolves them at QML
  # runtime instead (String.fromCharCode over a plain codepoint table), so
  # this is back to a straight copy -- and, not incidentally, that's also
  # what makes home/hyprland.nix's exec-once -c straight at this repo (for
  # quick reload while developing) show real icons instead of placeholder
  # text: there's no build step for them to depend on anymore.
  xdg.configFile."quickshell".source = ./quickshell;

  home.packages = [
    pkgs.quickshell

    # QML language server (qmlls) + formatter (qmlformat) for editing
    # quickshell's own QML config -- editor-side recognition wired up in
    # home/fresh.nix. kdePackages.* rather than the plain qt6.* namespace
    # to match this repo's existing convention (KDE window shortcuts,
    # polkit-kde-agent, etc. all already use kdePackages).
    pkgs.kdePackages.qtdeclarative

    # Panel typography (text) and icon glyphs (Phosphor, see
    # sysPanel/Phosphor.js) -- deliberately separate fonts/mechanisms, not
    # a Nerd Font mono like rofi/ghostty use, per the panel redesign.
    pkgs.jetbrains-mono
    phosphorFont

    # Real password/fingerprint auth for the lock screen
    # (lock/backends/AuthBackend.qml) -- drives the two dedicated PAM
    # services declared in configuration.nix (quickshell-lock/
    # quickshell-lock-fp) by feeding a typed password over stdin or just
    # waiting on the fingerprint conversation, and reading back the real
    # exit code. No QML-native PAM binding exists, so this is the same
    # "shell out to a small existing tool" idiom every other real backend
    # in this project already uses (scripts/list-apps.py etc.), just via
    # an existing nixpkgs package instead of a bespoke script.
    pkgs.pamtester
  ];
}

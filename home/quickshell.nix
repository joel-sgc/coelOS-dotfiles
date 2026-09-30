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
  # `quickshell` picks it up with no -p/-c flag needed. A straight copy --
  # icon glyphs are resolved at QML runtime by sysPanel/Phosphor.js
  # (String.fromCharCode over a codepoint table), not by a Nix-time
  # text-substitution pass, so there's no build step for them to depend on.
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
  ];
}

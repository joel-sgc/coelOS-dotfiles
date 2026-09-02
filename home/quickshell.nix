{ pkgs, ... }:

{
  # QtQuick/QML-based desktop shell toolkit. User-facing desktop tooling
  # (same category as waybar), not a system service, so it belongs here
  # rather than configuration.nix's environment.systemPackages -- moved
  # from there.
  #
  # ./quickshell/shell.qml is the actual config (a waybar-style top panel
  # -- see sysPanel/); this wires the whole directory to
  # ~/.config/quickshell, quickshell's default config search path, so
  # `quickshell` picks it up with no -p/-c flag needed.
  xdg.configFile."quickshell".source = ./quickshell;

  home.packages = [
    pkgs.quickshell

    # QML language server (qmlls) + formatter (qmlformat) for editing
    # quickshell's own QML config -- editor-side recognition wired up in
    # home/fresh.nix. kdePackages.* rather than the plain qt6.* namespace
    # to match this repo's existing convention (KDE window shortcuts,
    # polkit-kde-agent, etc. all already use kdePackages).
    pkgs.kdePackages.qtdeclarative
  ];
}

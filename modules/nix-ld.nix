{ pkgs, ... }:

{
  programs.nix-ld.enable = true;

  # Optional but recommended: give it a decent default library set
  # so it covers most foreign binaries (VS Code extensions, npm/pip
  # native tools, etc.), not just Claude Code.
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
    curl
    icu
    libunwind
    # add more here if a specific binary later complains about a
    # missing .so — the error message will name it
  ];
}
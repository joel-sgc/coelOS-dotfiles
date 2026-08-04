{ config, pkgs, ... }:

{
  imports = [
    ./git.nix
    ./pnpm.nix
  ];
}

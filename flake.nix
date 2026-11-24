{
  description = "CoelOS Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Frozen nixpkgs for the hand-vendored/out-of-band packages (Ultraleap,
    # the GlobalProtect FHS env). Their derivations hash in every dependency
    # (stdenv, glibc, bubblewrap, ...), so building them from the moving
    # `nixpkgs` input re-unpacks/re-patchelfs them on every `nix flake
    # update`. Built from this rev they never change. Bump it by hand (and
    # expect one rebuild) only when you actually want newer libs under them.
    nixpkgs-pinned.url = "github:NixOS/nixpkgs/2f5a153c270b70cb0f8c11f46d96d6d3bc39f4e3";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # Declarative per-game Steam config (Proton version, launch options,
    # DLL overrides, mod files). Steam has no home-manager module of its
    # own; this one patches Steam's config files for us. See home/steam.nix.
    steam-config-nix = {
      url = "github:different-name/steam-config-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-pinned = import inputs.nixpkgs-pinned {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Unit tests, run by `nix flake check` or one at a time with
      # `nix build .#checks.x86_64-linux.<name>`. They are the same suites as
      # `python3 tests/run.py <name>` (see tests/README.md); the sandbox gets the
      # interpreter each one needs (Lua 5.5 is the version Hyprland embeds).
      checks.${system} =
        let
          checkPkgs = nixpkgs.legacyPackages.${system};
          suite = name: tools:
            checkPkgs.runCommand "${name}-tests" { nativeBuildInputs = [ checkPkgs.python3 ] ++ tools; } ''
              export PYTHONDONTWRITEBYTECODE=1
              cd ${./.}
              python3 tests/run.py ${name} --nix never > "$TMPDIR/results.txt" || { cat "$TMPDIR/results.txt"; exit 1; }
              cat "$TMPDIR/results.txt"
              cp "$TMPDIR/results.txt" $out
            '';
        in
        {
          hyprland-grid = suite "hyprland-grid" [ checkPkgs.lua5_5 ];
          hyprland-settings = suite "hyprland-settings" [ checkPkgs.lua5_5 ];
          overview-layout = suite "overview-layout" [ checkPkgs.nodejs ];
          settings = suite "settings" [ ];
          gcast-castv2 = suite "gcast-castv2" [ checkPkgs.openssl ];
          gcast-discover = suite "gcast-discover" [ ];
          gcast-hls = suite "gcast-hls" [ ];
          miracast-wfd = suite "miracast-wfd" [ ];
          miracast-profiles = suite "miracast-profiles" [ ];
          miracast-linkd = suite "miracast-linkd" [ ];
          test-runner = suite "meta" [ ];
        };

      nixosConfigurations.coelos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          inherit pkgs-unstable pkgs-pinned;
        };
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.joelsgc = import ./home.nix;

            home-manager.extraSpecialArgs = {
              inherit inputs pkgs-pinned;
            };
          }
        ];
      };
    };
}

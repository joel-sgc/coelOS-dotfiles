{
  description = "CoelOS Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opencode.url = "github:GutMutCode/opencode-nix";

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    netpala.url = "github:joel-sgc/netpala";
    bluepala.url = "github:joel-sgc/bluepala";

    # Not in nixpkgs yet; the project ships its own flake (crane + fenix,
    # pins its own Rust toolchain independent of nixpkgs' rustc), so this is
    # a real declarative build straight from source, not a wrapped installer
    # script. First build compiles a substantial Rust codebase from
    # scratch -- expect it to take a while.
    #
    # Pinned to our own fork/branch rather than upstream: .tsx/.jsx files
    # were being parsed with the plain (non-JSX-capable) TypeScript grammar,
    # which broke JSX tag/attribute highlighting and indentation. Fix is up
    # as https://github.com/joel-sgc/fresh/tree/fix/tsx-grammar-and-jsx-indent
    # (not yet merged upstream) -- revert to sinelaw/fresh once it lands there.
    fresh.url = "github:joel-sgc/fresh/fix/tsx-grammar-and-jsx-indent";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      opencode,
      netpala,
      ...
    }:
    {
      nixosConfigurations.coelos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          netpala.nixosModules.default
          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.joelsgc = import ./home.nix;

            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
          }
        ];
      };
    };
}

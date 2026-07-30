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
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
  {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./configuration.nix

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

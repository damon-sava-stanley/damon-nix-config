{
  description = "NixOS configuration for deeley";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.deeley = nixpkgs.lib.nixosSystem {
        inherit system;

        modules = [
          ./hosts/deeley
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.damon = import ./home/damon;
            };
          }
        ];
      };

      checks.${system}.deeley = self.nixosConfigurations.deeley.config.system.build.toplevel;
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}


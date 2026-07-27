{
  description = "NixOS configuration for deeley";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
    }:
    let
      system = "x86_64-linux";
      unstablePkgs = import nixpkgs-unstable {
        inherit system;
      };
    in
    {
      nixosConfigurations.deeley = nixpkgs.lib.nixosSystem {
        inherit system;

        modules = [
          ./hosts/deeley
          home-manager.nixosModules.home-manager
          {
            nixpkgs.config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "brave"
                "dropbox"
                "firefox-bin"
                "firefox-bin-unwrapped"
              ];

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit unstablePkgs;
              };
              users.damon = import ./home/damon;
            };
          }
        ];
      };

      checks.${system}.deeley = self.nixosConfigurations.deeley.config.system.build.toplevel;
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}

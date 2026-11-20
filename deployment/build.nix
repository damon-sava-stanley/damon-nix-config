{ applicationSource, applicationRevision }:
let
  captured = import ./inputs.nix;
  host = import ./resolved-flake.nix captured;
  recipe = host.inputs.remote-zettel-software + "/nix/remote-zettel-package.nix";
in (host.nixosConfigurations.deeley.extendModules {
  modules = [ ({ lib, pkgs, ... }: {
    services.remote-zettel.selfDeployment.nixos.buildFile = lib.mkForce ./build.nix;
    services.remote-zettel.package = lib.mkForce (import recipe {
      inherit pkgs applicationSource applicationRevision;
    });
  }) ];
}).config.system.build.toplevel

# Application releases use the separately captured host; runtime policy stays fixed.
{ config, lib, pkgs, remote-zettel-software, ... }:
let
  app = config.services.remote-zettel;
  publication = app.repositoryInstances.remote-zettel.publication.plan;
  buildFile = app.selfDeployment.nixos.buildFile;
  generation = lib.optionalString (app.selfDeployment.stateGeneration != null) "-${app.selfDeployment.stateGeneration}";
  controllerState = "/var/lib/remote-zettel-self-deployment${generation}";
  deliveryState = "/var/lib/remote-zettel-deployment-delivery${generation}";
  adapter = import ./remote-zettel-private-deployment-adapter.nix {
    inherit pkgs buildFile;
    stateDirectory = "${controllerState}/nixos-generations";
    runtimeSource = remote-zettel-software.outPath;
    sshConfigurationFile = app.repositoryInstances.remote-zettel.publication.sshConfigurationFile;
    target = "deeley"; repository = "damon-sava-stanley/remote-zettel";
    healthPort = lib.toInt config.systemd.services.remote-zettel.environment.PORT;
  };
  policy = builtins.fromJSON (builtins.readFile ../../deployments/remote-zettel-publication.json);
in {
  imports = [ remote-zettel-software.nixosModules.self-deployment ];
  nix.settings.build-users-group = lib.mkDefault "nixbld";
  system.build.remoteZettelPrivateDeploymentAdapter = adapter;
  assertions = [
    { assertion = policy.owner.generation == app.repositoryInstances.remote-zettel.epoch
          && policy.publication.publication.generation == app.repositoryInstances.remote-zettel.epoch;
      message = "Commission the software publication policy before enabling a new deployment bridge."; }
    { assertion = config.nix.settings.sandbox && !lib.elem config.nix.settings.build-users-group [ "" "root" ];
      message = "Private self deployment requires sandboxed builds and separate build users."; }
    { assertion = lib.hasPrefix "/nix/store/" (toString buildFile);
      message = "Private self deployment requires an immutable trusted host build."; }
  ];
  system.build.remoteZettelSelfDeploymentInitialize = pkgs.writeShellScriptBin "initialize-remote-zettel-deployment" ''
    set -euo pipefail
    test "$EUID" = 0 || { echo 'Root commissioning required' >&2; exit 1; }
    for path in ${controllerState} ${deliveryState}; do
      if test -L "$path"; then echo 'Symlinked deployment state refused' >&2; exit 1; fi
      if test -e "$path"; then
        test "$(${pkgs.coreutils}/bin/stat -c %u:%g:%a "$path")" = 0:0:700 || { echo 'Unprotected deployment state refused' >&2; exit 1; }
      else
        ${pkgs.coreutils}/bin/install -d -m 0700 "$path"
      fi
    done
    for file in ${controllerState}/state.sqlite ${deliveryState}/delivery.sqlite; do
      test ! -e "$file" && test ! -L "$file" || { echo 'Existing deployment journals: inspect without resetting them' >&2; exit 1; }
    done
    ${app.selfDeployment.automatic.initializeCommand}
    echo 'Deployment journals commissioned; ready for the reviewed system switch.'
  '';
  services.remote-zettel = {
    softwarePublication.enable = true;
    selfDeployment = {
      enable = true;
      target = "deeley";
      repository = "damon-sava-stanley/remote-zettel";
      commandTimeoutSeconds = 1800;
      adapterCommand = "${adapter}/bin/remote-zettel-private-nixos-adapter";
      nixos = {
        enable = false;
        buildFile = import ../../deployments/remote-zettel-deployment-host.nix;
        sourceUrl = "https://github.com/damon-sava-stanley/remote-zettel.git";
        service = "remote-zettel.service";
        healthPort = lib.toInt config.systemd.services.remote-zettel.environment.PORT;
        healthTimeoutSeconds = 30;
      };
      automatic = {
        enable = true;
        package = remote-zettel-software.packages.${pkgs.stdenv.hostPlatform.system}.default;
        runtimeSource = remote-zettel-software.outPath;
        inherit (policy) owner publication;
        publisherSocket = publication.paths.outcome;
        publisherUnit = "${publication.prefix}-owner";
        statusClientUid = config.users.users.remote-zettel.uid;
        exposeWorkStatus = true;
      };
    };
  };
}

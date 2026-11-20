# The operator retains its target; the system must not depend on the operator.
{ pkgs, targetConfig }:
let
  app = targetConfig.services.remote-zettel;
  retain = path: builtins.appendContext path { "${path}" = { path = true; }; };
  previousPlan = retain "/nix/store/hnakak3bdpw7x8wkr7s2lzi08pivh59w-host-policy-transition-plan.json";
  previous = builtins.fromJSON (builtins.readFile ../../deployment/host-policy-prepared-plan.json);
  plan = pkgs.writeText "resume-host-deployment-plan.json" (builtins.toJSON {
    version = 1;
    inherit previousPlan;
    previousOperatorScripts = retain "/nix/store/f92c9dbzqfgkcc8v7gwvr0w252p8szc9-work-host-policy-upgrade-scripts";
    sourceSystem = retain "/nix/store/ybvf0abdf9cg9717j4b3264pxn8dsgc6-nixos-system-deeley-26.05.20261118.3457b69";
    targetSystem = targetConfig.system.build.toplevel;
    stateDirectory = "/var/lib/remote-zettel-host-upgrades/host-20261119/deployment-resume";
    publicPolicy = "/var/lib/remote-zettel-host-upgrade-public/host-20261119/publication.json";
    bridgeConfiguration = targetConfig.environment.etc."remote-zettel-self-deployment/bridge.json".source;
    node = "${pkgs.nodejs_24}/bin/node";
    application = "${app.selfDeployment.automatic.package}/lib/remote-zettel";
    applicationRevision = (builtins.fromJSON (builtins.readFile "${app.package}/lib/remote-zettel/build-revision.json")).commit;
    adapterConfiguration = targetConfig.system.build.remoteZettelPrivateDeploymentAdapter.configuration;
    adapterImplementation = app.selfDeployment.automatic.runtimeSource + "/scripts/nixos-deployment-adapter.py";
    runtimeHelper = ../../scripts/resume-host-deployment.mjs;
    systemctl = "${pkgs.systemd}/bin/systemctl";
    nixEnv = "${pkgs.nix}/bin/nix-env";
    runuser = "${pkgs.util-linux}/bin/runuser";
    workCli = "${app.package}/bin/work";
    repositories = previous.repositories;
    requiredUnits = previous.newUnits ++ [ "remote-zettel-deployment-status.service" ];
  });
in pkgs.writeShellScriptBin "resume-host-deployment" ''
  test "$#" = 0 || { echo 'No arguments accepted' >&2; exit 2; }
  exec ${pkgs.python3}/bin/python3 -I ${../../scripts/resume-host-deployment.py} ${plan}
''

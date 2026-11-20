# App changes must not rebind controller, publisher, or execution authority.
{ pkgs, systemConfig, variants, deploymentHeld ? false }:
let
  app = systemConfig.services.remote-zettel;
  controller = cfg: toString cfg.services.remote-zettel.selfDeployment.controllerConfigurationFile;
  writer = cfg: toString cfg.services.remote-zettel.workPilot.writerDefinitions;
  software = cfg: toString cfg.services.remote-zettel.repositoryInstances.remote-zettel.plan.stateConfiguration;
  command = cfg: unit: cfg.systemd.services.${unit}.serviceConfig.ExecStart;
  stable = cfg: (deploymentHeld || controller cfg == controller systemConfig)
    && writer cfg == writer systemConfig && software cfg == software systemConfig
    && pkgs.lib.all (unit: command cfg unit == command systemConfig unit) ([
      "remote-zettel-work-remote-zettel-host-20261119-pub-owner"
      "remote-zettel-work-epoch-host-20261119-namespace-host"
      "remote-zettel-work-instance-remote-zettel-host-20261119-host"
    ] ++ pkgs.lib.optional (!deploymentHeld) "remote-zettel-deployment-bridge");
  bridge = systemConfig.systemd.services.remote-zettel-deployment-bridge;
in
assert app.softwarePublication.enable && app.repositoryInstances.remote-zettel.publication.enable;
assert app.repositoryInstances.remote-zettel.publication.deploymentEvidence;
assert if deploymentHeld then !app.selfDeployment.enable && !app.selfDeployment.automatic.enable
  && !(systemConfig.systemd.services ? remote-zettel-deployment-bridge)
  && systemConfig.environment.etc ? "remote-zettel-host-software-transition.json"
  else app.selfDeployment.enable && app.selfDeployment.automatic.enable;
assert app.selfDeployment.automatic.owner.ref == "refs/heads/main";
assert app.selfDeployment.automatic.publication.publication.repository == "damon-sava-stanley/remote-zettel";
assert writer systemConfig == "/nix/store/xyaixx5d1vsfqfc3arfaspwrshk6ksis-epoch-host-20261119-writer-definitions";
assert software systemConfig == "/nix/store/630dpr0wrjm4ygcqahidi13vi538yjq1-remote-zettel-work-instance-remote-zettel-host-20261119-state.json";
assert deploymentHeld || (!bridge.restartIfChanged && !bridge.stopIfChanged && bridge.partOf == []);
assert deploymentHeld || bridge.unitConfig.ConditionPathExists == "!/var/lib/remote-zettel-self-deployment/operator-recovery";
assert pkgs.lib.all stable variants;
assert toString (builtins.elemAt variants 0).services.remote-zettel.package != toString (builtins.elemAt variants 1).services.remote-zettel.package;
pkgs.runCommandLocal "deeley-self-deployment-policy-invariance" {} ''
  touch "$out"
''

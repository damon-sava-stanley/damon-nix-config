# App changes must not rebind controller, publisher, or execution authority.
{ pkgs, systemConfig, variants }:
let
  app = systemConfig.services.remote-zettel;
  controller = cfg: toString cfg.services.remote-zettel.selfDeployment.controllerConfigurationFile;
  writer = cfg: toString cfg.services.remote-zettel.workPilot.writerDefinitions;
  software = cfg: toString cfg.services.remote-zettel.repositoryInstances.remote-zettel.plan.stateConfiguration;
  command = cfg: unit: cfg.systemd.services.${unit}.serviceConfig.ExecStart;
  stable = cfg: controller cfg == controller systemConfig
    && writer cfg == writer systemConfig && software cfg == software systemConfig
    && pkgs.lib.all (unit: command cfg unit == command systemConfig unit) [
      "remote-zettel-deployment-bridge" "remote-zettel-work-remote-zettel-pub-owner"
      "remote-zettel-work-epoch-agent-approval-v1-namespace-host"
      "remote-zettel-work-instance-remote-zettel-host"
    ];
  bridge = systemConfig.systemd.services.remote-zettel-deployment-bridge;
in
assert app.softwarePublication.enable && app.repositoryInstances.remote-zettel.publication.enable;
assert app.repositoryInstances.remote-zettel.publication.deploymentEvidence;
assert app.selfDeployment.enable && app.selfDeployment.automatic.enable;
assert app.selfDeployment.automatic.owner.ref == "refs/heads/main";
assert app.selfDeployment.automatic.publication.publication.repository == "damon-sava-stanley/remote-zettel";
assert writer systemConfig == "/nix/store/p12n3rvljxbivvbmy393xkp6cr4yawlg-epoch-agent-approval-v1-writer-definitions";
assert software systemConfig == "/nix/store/vlhi5vlavmxr233xw3a1bhkb0fbvq7zv-remote-zettel-work-instance-remote-zettel-state.json";
assert !bridge.restartIfChanged && !bridge.stopIfChanged && bridge.partOf == [];
assert bridge.unitConfig.ConditionPathExists == "!/var/lib/remote-zettel-self-deployment/operator-recovery";
assert pkgs.lib.all stable variants;
assert toString (builtins.elemAt variants 0).services.remote-zettel.package != toString (builtins.elemAt variants 1).services.remote-zettel.package;
pkgs.runCommandLocal "deeley-self-deployment-policy-invariance" {} ''
  touch "$out"
''

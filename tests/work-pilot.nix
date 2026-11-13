{ pkgs, lib, systemConfig, webPackage, runtimePackage, runtimeSource }:
let
  app = systemConfig.services.remote-zettel;
  pilot = app.workPilot;
  services = systemConfig.systemd.services;
  web = services.remote-zettel;
  ns = "remote-zettel-work-epoch-task-lifecycle-v1-namespace";
in
assert toString app.package == toString webPackage;
assert toString pilot.package == toString runtimePackage;
assert toString app.publisherOutcomeService.package == toString runtimePackage;
assert toString pilot.runtimeSource == toString runtimeSource;
assert pilot.enable && pilot.enableExecution && pilot.enableContinuation && pilot.enableStructuredInput;
assert pilot.epoch == "task-lifecycle-v1";
assert toString pilot.retiredEpochs.publication-v2 == "/nix/store/c75zkanwrvzflbwrns8dsski05m94grn-epoch-publication-v2-writer-definitions";
assert pilot.repository == "damon-sava-stanley/ssdamon-stories";
assert pilot.baseCommit == "3689bb4c647704ca4c2d658b3e0e8a839eb6a116";
assert pilot.baseCommitFile == "/var/lib/remote-zettel-task-lifecycle-v1/source-state/base";
assert pilot.documentsRoot == "/home/damon/Dropbox/agent-workspace-task-lifecycle-v1";
assert lib.hasInfix "check-writing-worktree.py" pilot.checkCommand;
assert lib.hasInfix "check-writing-candidate.py" pilot.candidateCheckCommand;
assert app.reusablePublication.enable && app.upgrade.enable;
assert app.upgrade.previous.epoch == "publication-v2";
assert app.upgrade.previous.coordinatorStatePath == "/var/lib/remote-zettel/work/publication-v2/state.sqlite";
assert systemConfig.system.preSwitchChecks ? remote-zettel-work-upgrade;
assert web.environment.WORK_FAKE_WORKER == "false";
assert web.environment.WORK_SHARED_DOCUMENTS == "true";
assert web.environment.WORK_HISTORY_ROOT == "/var/lib/remote-zettel-history";
assert web.environment.WORK_STATE_PATH == "/var/lib/remote-zettel/work/task-lifecycle-v1/state.sqlite";
assert web.environment.ORIGIN_PUBLIC_HOSTNAME == "zettel.ss-damon.com";
assert app.cloudflareAccess != null;
assert lib.elem "remote-zettel-work-upgrade.service" web.requires;
assert lib.hasInfix (builtins.unsafeDiscardStringContext (toString runtimePackage)) services."${ns}-host".serviceConfig.ExecStart;
assert services."${ns}-host".serviceConfig.User == "remote-zettel-work-host";
assert services."${ns}-proxy".serviceConfig.Group == "remote-zettel-work";
assert services."${ns}-executor-supervisor".serviceConfig.User == "root";
assert services."${ns}-executor-check-operation@".serviceConfig.User == "agent";
assert services."${ns}-executor-check-operation@".serviceConfig.PrivateNetwork;
assert lib.elem "/var/lib/${ns}-host/credentials.sqlite" services."${ns}-host".unitConfig.ConditionPathExists;
assert lib.elem "/var/lib/remote-zettel-epoch-activation/task-lifecycle-v1/enrolled" services."${ns}-host".unitConfig.ConditionPathIsDirectory;
pkgs.runCommandLocal "work-pilot-live-configuration-check" {} ''
  touch "$out"
''

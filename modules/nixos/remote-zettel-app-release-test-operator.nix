# One exact test of the existing human approval/publication/deployment pipeline.
{ pkgs, targetConfig }:
let
  lib = pkgs.lib;
  app = targetConfig.services.remote-zettel;
  instance = app.repositoryInstances.remote-zettel;
  def = builtins.fromJSON (builtins.readFile ../../deployments/app-release-test.json);
  retain = path: builtins.appendContext path { "${path}" = { path = true; }; };
  units = map (name: "${name}.service") (lib.filter (name:
    lib.hasPrefix (instance.plan.prefix + "-") name || lib.hasPrefix (instance.publication.plan.prefix + "-") name)
    (builtins.attrNames targetConfig.systemd.services)) ++ [ "remote-zettel.service" ];
  bridgeFile = targetConfig.environment.etc."remote-zettel-self-deployment/bridge.json".source;
  bridge = builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile bridgeFile));
  manifest = pkgs.writeText "start-app-release-test-plan.json" (builtins.toJSON {
    version = 1;
    inherit (def) oldBase newBase taskId taskRevision repository;
    packRoot = retain def.packRoot;
    system = targetConfig.system.build.toplevel;
    inherit units bridge;
    oldUnits = units ++ [ "remote-zettel-deployment-bridge.service" "remote-zettel-self-deployment.service" ];
    transientPrefixes = [ (instance.plan.prefix + "-") (instance.publication.plan.prefix + "-") ];
    startUnits = instance.publication.plan.dependencies ++ map (suffix: "${instance.plan.prefix}-${suffix}.service")
      [ "host" "proxy" "content-proxy" "repository-read" "executor-supervisor" ] ++ [ "remote-zettel.service" ];
    stateDirectory = "/var/lib/remote-zettel-host-upgrades/host-20261119/app-release-test";
    hold = "/var/lib/remote-zettel-self-deployment/operator-recovery";
    inherit (instance) documentsRoot coordinatorStatePath;
    hostRoot = instance.plan.paths.host;
    executorRoot = instance.plan.paths.executor;
    sourceConfiguration = instance.publication.plan.topology.sourceConfiguration;
    sourcePin = "/var/lib/remote-zettel-software-source-policy-host-20261119/source-pin.json";
    baseFile = instance.baseCommitFile;
    inherit (instance.publication) publisherStorePath ingestionDirectory;
    sourceVerifier = "${targetConfig.system.build.remoteZettelSoftwareSourceCommission}/bin/remote-zettel-software-commission-source";
    bootstrapHelper = ../../scripts/remote-zettel-publication-bootstrap.py;
    readinessHelper = ../../scripts/resume-host-deployment.py;
    taskHelper = ../../scripts/release-test-task.py;
    taskDocument = pkgs.writeText "app-release-test-task.md" def.document;
    queueInput = pkgs.writeText "app-release-test-queue.json" (builtins.toJSON { revision = def.taskRevision; previousRunId = null; });
    observerHelper = ../../scripts/release-test-observer.py;
    statusHelper = ../../scripts/release-test-status.mjs;
    observerDirectory = "/var/lib/remote-zettel-app-release-test-observer";
    node = "${pkgs.nodejs_24}/bin/node";
    python = "${pkgs.python3}/bin/python3";
    application = "${app.selfDeployment.automatic.package}/lib/remote-zettel";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    systemdRun = "${pkgs.systemd}/bin/systemd-run";
    runuser = "${pkgs.util-linux}/bin/runuser";
    webUid = targetConfig.users.users.remote-zettel.uid;
    webGid = targetConfig.users.groups.remote-zettel.gid;
    workCli = "${app.package}/bin/work";
    controlSocket = "/run/remote-zettel/work-control/control.sock";
    repositories = [ app.workPilot.repository instance.repository ];
  });
in pkgs.writeShellScriptBin "start-app-release-test" ''
  test "$#" = 0 || { echo 'No arguments accepted' >&2; exit 2; }
  exec ${pkgs.python3}/bin/python3 -I ${../../scripts/start-app-release-test.py} ${manifest}
''

{ pkgs, lib, systemConfig, release }:
let
  pilot = systemConfig.services.remote-zettel.workPilot or {};
  services = systemConfig.systemd.services;
  web = services.remote-zettel;
in
assert lib.assertMsg (release == "a07a6894b2df9dd8a7875e9764314e058f8b222a") "Work pilot must use the approved release";
assert lib.assertMsg (pilot.enable or false) "Work pilot services must be explicitly enabled";
assert lib.assertMsg (!(pilot.enableExecution or true)) "Real queueing must remain disabled during preparation";
assert pilot.baseCommit == "bb48c49b1ddeba9a8f6934b505d553dafbf9094b";
assert pilot.documentsRoot == "/home/damon/Dropbox/agent-workspace";
assert pilot.checkCommand == "test -d drafts && git diff --check";
assert !(web.environment ? WORK_PI_ENROLLMENT);
assert web.environment.WORK_FAKE_WORKER == "false";
assert web.environment.WORK_SHARED_DOCUMENTS == "true";
assert web.environment.WORK_STATE_PATH == "/var/lib/remote-zettel/work/state.sqlite";
assert web.environment.ORIGIN_PUBLIC_HOSTNAME == "zettel.ss-damon.com";
assert systemConfig.services.remote-zettel.cloudflareAccess != null;
assert services.remote-zettel-work-host.serviceConfig.User == "remote-zettel-work-host";
assert services.remote-zettel-work-proxy.serviceConfig.Group == "remote-zettel-work";
assert services.remote-zettel-work-executor-supervisor.serviceConfig.User == "root";
assert services."remote-zettel-work-executor-check-operation@".serviceConfig.User == "agent";
assert services."remote-zettel-work-executor-check-operation@".serviceConfig.PrivateNetwork;
assert services.remote-zettel-work-host.unitConfig.ConditionPathExists == "/var/lib/remote-zettel-work-host/credentials.sqlite";
pkgs.runCommandLocal "work-pilot-preparation-check" {} ''
  touch "$out"
''

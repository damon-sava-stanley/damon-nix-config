# Separate operator package avoids a system-closure -> operator -> system cycle.
{ pkgs, prepared, active }:
let
  instance = active.services.remote-zettel.repositoryInstances.remote-zettel;
  sourceConfiguration = builtins.fromJSON (builtins.readFile instance.plan.stateConfiguration);
  prefix = instance.plan.prefix;
  probeCode = pkgs.writeText "remote-zettel-auth-presence.mjs" ''
    import { AstraCredentialStore } from '${instance.package}/lib/remote-zettel/src/work/astra-credentials.js';
    let store;
    try {
      store = new AstraCredentialStore('${instance.plan.paths.host}/credentials.sqlite');
      process.exitCode = (await store.read('openai'))?.type === 'oauth' ? 0 : 3;
    } catch { console.error('Dedicated authentication could not be checked.'); process.exitCode = 1; }
    finally { store?.close(); }
  '';
  probe = pkgs.writeShellScript "remote-zettel-auth-presence" ''
    exec ${pkgs.nodejs_24}/bin/node ${probeCode}
  '';
  plan = pkgs.writeText "deeley-remote-zettel-enrollment-plan.json" (builtins.toJSON {
    hostname = active.networking.hostName;
    repository = instance.repository;
    preparedSystem = toString prepared.system.build.toplevel;
    executionSystem = toString active.system.build.toplevel;
    commissionSource = "${active.system.build.remoteZettelSoftwareSourceCommission}/bin/remote-zettel-software-commission-source";
    guard = toString instance.plan.guard;
    stateConfiguration = toString instance.plan.stateConfiguration;
    policyDigest = sourceConfiguration.policyDigest;
    policyMarker = instance.plan.paths.policy + "/policy.json";
    hostLedger = instance.plan.paths.host + "/admission.sqlite";
    credentials = instance.plan.paths.host + "/credentials.sqlite";
    authProbe = toString probe;
    hostUser = instance.plan.identities.host.user;
    hostUnit = "${prefix}-host.service";
    hostUid = instance.identities.host.uid;
    hostGid = instance.identities.host.gid;
    login = "${instance.plan.login}/bin/${prefix}-login";
    sourceRoots = [ "/var/lib/remote-zettel-software-source" "/var/lib/remote-zettel-software-source-state" "/var/lib/remote-zettel-software-source-policy" ];
    operatorState = "/var/lib/remote-zettel-software-enrollment";
    currentSystem = "/run/current-system";
    systemProfile = "/nix/var/nix/profiles/system";
    nixEnv = "${pkgs.nix}/bin/nix-env";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    runuser = "${pkgs.util-linux}/bin/runuser";
    prepareUnit = "${prefix}-prepare.service";
    units = map (suffix: "${prefix}-${suffix}.service") [ "host" "executor-supervisor" "proxy" "content-proxy" "repository-read" ];
    webUser = "remote-zettel";
    workCli = "${active.services.remote-zettel.package}/bin/work";
    controlSocket = "/run/remote-zettel/work-control/control.sock";
  });
in
assert toString prepared.services.remote-zettel.repositoryInstances.remote-zettel.plan.stateConfiguration
  == toString instance.plan.stateConfiguration;
pkgs.writeShellScriptBin "enroll-remote-zettel" ''
  test "$#" = 0 || { echo 'No arguments accepted' >&2; exit 2; }
  exec ${pkgs.python3}/bin/python3 -I ${../../scripts/remote-zettel-enrollment.py} ${plan}
''

{ config, lib, pkgs, remote-zettel-software, ... }:
let
  before = builtins.fromJSON (builtins.readFile ./host-policy-before.json);
  epoch = "host-20261120";
  state = "/var/lib/remote-zettel-host-upgrades/${epoch}";
  retain = path: builtins.appendContext path { "${path}" = { path = true; }; };
  writer = name: path: rec {
    type = "derivation"; inherit name; outPath = retain path;
    outputs = [ "out" ]; outputName = "out"; out = value;
    value = { inherit type name outPath outputs outputName; };
  };
  instance = config.services.remote-zettel.repositoryInstances.remote-zettel;
  targetSSH = builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile instance.publication.sshConfigurationFile));
  primarySSH = pkgs.writeText "host-policy-stories-ssh.json" (builtins.toJSON (before.primarySSH // {
    inherit (targetSSH) python helper git ssh bpftool systemdRun systemctl;
    shell = "${pkgs.bash}/bin/sh";
    knownHosts = retain before.primarySSH.knownHosts;
    passwd = retain before.primarySSH.passwd;
  }));
  secondary = import (remote-zettel-software + "/nix/work-software-transition.nix") {
    inherit pkgs instance epoch;
    commissionPlan = config.system.build.remoteZettelSoftwarePublicationPlan;
    previous = before.softwarePrevious;
    sourcePin = "/var/lib/remote-zettel-software-source-policy-${epoch}/source-pin.json";
    stateDirectory = "${state}/software";
    runtimeSource = remote-zettel-software.outPath;
  };
in {
  services.remote-zettel = {
    workPilot = {
      epoch = lib.mkForce epoch;
      coordinatorStatePath = lib.mkForce "/var/lib/remote-zettel/work/${epoch}/state.sqlite";
      documentsRoot = lib.mkForce "/home/damon/Dropbox/agent-workspace-${epoch}";
      retiredEpochs = lib.mkForce (lib.mapAttrs (name: path: writer "epoch-${name}-writer-definitions" path)
        (before.generation.retired // { ${before.generation.epoch} = before.generation.bundle; }));
    };
    upgrade.previous = lib.mkForce {
      inherit (before.upgrade) epoch root hostRoot documentsRoot coordinatorStatePath
        publisherStorePath ingestionDirectory approvalConfigurationFile publisherConfigurationFile;
      executorRoot = "/var/lib/${builtins.baseNameOf (builtins.dirOf before.storiesEnrollment.profile.supervisorSocket)}";
      sourceRepository = before.upgrade.topology.sourceConfiguration.repository;
      sourceStateDirectory = before.upgrade.topology.sourceConfiguration.stateDirectory;
      writerDefinitions = writer "epoch-agent-approval-v1-writer-definitions" before.generation.bundle;
    };
    upgrade.sshConfigurationFile = primarySSH;
    upgrade.dispatcher = builtins.dirOf targetSSH.helper + "/ssh-publication-owner-dispatch.py";
    repositoryInstances.remote-zettel = {
      inherit epoch;
      sourceRepository = lib.mkForce "/var/lib/remote-zettel-software-source-${epoch}";
      baseCommitFile = lib.mkForce "/var/lib/remote-zettel-software-source-state-${epoch}/base";
    };
    selfDeployment = {
      # Fresh journals and the refreshed captured host are commissioned by the
      # separate resume operator. The global maintenance hold gates startup.
      enable = lib.mkForce true;
      automatic.enable = lib.mkForce true;
      stateGeneration = "${epoch}-v2";
    };
  };
  environment.etc."remote-zettel-host-software-transition.json".source = secondary.manifest;
  system.build.remoteZettelHostTransitionScripts = secondary.scripts;
  system.extraDependencies = secondary.retain ++ [ (retain before.sourceSystem) (pkgs.writeText "human-review-policy.patch" (builtins.readFile ../deployments/human-review-policy.patch)) ];
  system.preSwitchChecks.remote-zettel-host-software-transition = ''
    ${secondary.checkCommand}
  '';
}

# Separate, explicitly commissioned publisher for the software repository.
{ config, lib, pkgs, remote-zettel-software, ... }:
let
  app = config.services.remote-zettel;
  instance = app.repositoryInstances.remote-zettel;
  cfg = app.softwarePublication;
  runtime = remote-zettel-software.outPath;
  package = remote-zettel-software.packages.${pkgs.stdenv.hostPlatform.system}.default;
  application = "${package}/lib/remote-zettel";
  root = "/var/lib/remote-zettel-software-publication";
  tools = pkgs.linkFarm "remote-zettel-software-publication-tools" (map (name: {
    inherit name; path = runtime + "/scripts/${name}";
  }) [ "publisher-candidate-promotion.py" "publisher-candidate-wire.py" "publisher-candidate-sandbox.py"
    "prepare-publisher-candidate.py" "verify-candidate.py" "epoch-snapshot-sqlite.py"
    "local-publication-git.py" "local-publication-wire.py" "local-publication-sandbox.py" "publication-owner-dispatch.py"
    "ssh-publication-git.py" "ssh-publication-sandbox.py" "ssh-publication-owner-dispatch.py" "ssh-publication-network.py"
    "epoch-review-provenance-sandbox.py" "epoch-review-provenance-wire.py" ]);
  # GitHub /meta, retrieved 2026-11-18. The transport uses this fixed alias.
  knownHosts = pkgs.writeText "github-publication-known-hosts" ''
    publication-target ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  '';
  connection = { host = "github.com"; address = "140.82.114.4"; port = 22;
    user = "git"; repository = "/damon-sava-stanley/remote-zettel.git"; };
  ssh = pkgs.writeText "remote-zettel-software-publication-ssh.json" (builtins.toJSON {
    version = 1; kind = "ssh-publication-owner-config-v1"; inherit connection knownHosts;
    credential = "${root}-key/identity"; publisherUid = 3311;
    shell = "${pkgs.bash}/bin/sh"; python = "${pkgs.python3}/bin/python3";
    helper = "${tools}/ssh-publication-sandbox.py"; git = "${pkgs.git}/bin/git"; ssh = "${pkgs.openssh}/bin/ssh";
    passwd = pkgs.writeText "remote-zettel-software-publisher-passwd" "publisher:x:3311:3311:publisher:/tmp:/bin/sh\n";
    bpftool = "${pkgs.bpftools}/bin/bpftool";
    systemdRun = "${pkgs.systemd}/bin/systemd-run"; systemctl = "${pkgs.systemd}/bin/systemctl";
  });
  ingest = import (runtime + "/nix/work-candidate-ingest.nix") { inherit pkgs; };
  pin = import (runtime + "/nix/work-publication-ingestion-pin.nix") {
    inherit pkgs; app = application; tools = ingest.tools;
    enrollment = instance.plan.enrollment; repository = instance.repository;
    repositoryId = "remote-zettel"; generation = "software-publication-v1";
    directory = "${root}/ingestion";
    importerUser = "rzwi-remote-zettel-importer"; importerUid = 3310; importerGid = 3313;
    endpoint = "/run/remote-zettel-work-remote-zettel-pub-bundle/read.sock";
    serverUid = instance.identities.host.uid;
  };
  publication = {
    enable = cfg.enable;
    deploymentEvidence = true;
    inherit package;
    runtimeSource = runtime;
    identities = { importer = { uid = 3310; gid = 3310; }; publisher = { uid = 3311; gid = 3311; };
      transport.gid = 3312; bundle.gid = 3313; };
    ingestionConfigurationFile = "${root}/config/ingestion-service.json";
    ingestionWriterConfigurationFile = "${root}/config/ingestion.json";
    ingestionDirectory = "${root}/ingestion";
    ingestionPolicySha256 = builtins.readFile "${pin}/policy";
    publisherConfigurationFile = "${root}/config/operator.json";
    publisherStorePath = "${root}/publisher/state.sqlite";
    approvalConfigurationFile = "${root}/config/approval.json";
    sourceStateDirectory = "/var/lib/remote-zettel-software-source-state";
    acknowledgmentSourceDigest = builtins.hashString "sha256" "remote-zettel-software-publication-acknowledgment-v1";
    sshConfigurationFile = toString ssh;
  };
  plan = import (runtime + "/nix/work-repository-publication.nix") {
    inherit pkgs package; name = "remote-zettel"; repository = instance.repository;
    execution = instance.plan; runtimeSource = runtime;
    config = builtins.removeAttrs publication [ "enable" "package" "runtimeSource" ];
    clientUid = config.users.users.remote-zettel.uid;
  };
  reusable = plan.topology // { sourcePin = "/var/lib/remote-zettel-software-source-policy/source-pin.json"; };
  access = { issuer = "https://${app.cloudflareAccess.teamDomain}"; inherit (app.cloudflareAccess) audience; };
  commissioner = import (runtime + "/nix/work-publication-commission.nix") {
    inherit pkgs access reusable; app = application;
    enrollment = instance.plan.enrollment;
    applicationUid = config.users.users.remote-zettel.uid;
    dispatcher = "${tools}/ssh-publication-owner-dispatch.py";
    publisherUid = 3311; forbiddenUids = [ 0 989 987 988 3202 3301 3302 3303 3304 3310 ];
  };
  commissionPlan = pkgs.writeText "remote-zettel-software-publication-plan.json" (builtins.toJSON {
    version = 1; inherit root access connection knownHosts reusable;
    repository = instance.repository; repositoryId = "remote-zettel"; generation = "software-publication-v1";
    enrollment = instance.plan.enrollment; ingestionPin = "${pin}/pin.json";
    sshConfiguration = ssh;
    commissioner = "${commissioner}/bin/work-publication-commission";
    inherit (publication) ingestionConfigurationFile ingestionWriterConfigurationFile ingestionDirectory
      publisherConfigurationFile publisherStorePath approvalConfigurationFile;
    publicationPaths = plan.paths;
    releaseSocket = "/run/${plan.prefix}-release/read.sock";
    publisherUid = 3311; applicationUid = config.users.users.remote-zettel.uid;
    applicationGid = config.users.groups.remote-zettel.gid;
    application = application;
    node = "${pkgs.nodejs_24}/bin/node";
    python = "${pkgs.python3}/bin/python3";
    git = "${pkgs.git}/bin/git";
    sshKeygen = "${pkgs.openssh}/bin/ssh-keygen";
    runuser = "${pkgs.util-linux}/bin/runuser";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    ingest = "${ingest}/bin/work-candidate-ingest";
  });
in {
  options.services.remote-zettel.softwarePublication.enable = lib.mkEnableOption "the separately commissioned software publisher";
  config = {
    services.remote-zettel.repositoryInstances.remote-zettel.publication = publication;
    system.build.remoteZettelSoftwarePublicationPlan = commissionPlan;
  };
}

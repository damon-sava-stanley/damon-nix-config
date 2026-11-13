{ pkgs, lib, remote-zettel, remote-zettel-runtime, ... }:

let
  # Retain the commissioned predecessor definitions for the automatic handoff.
  # Explicit context retains an existing store object without impure storePath
  # lookup. These are enrolled deployment artifacts, not bootstrap downloads.
  retain = path: builtins.appendContext path { "${path}" = { path = true; }; };
  previousWriters = rec {
    type = "derivation";
    name = "epoch-publication-v2-writer-definitions";
    outPath = retain "/nix/store/c75zkanwrvzflbwrns8dsski05m94grn-epoch-publication-v2-writer-definitions";
    outputs = [ "out" ]; outputName = "out"; out = previousWriters;
  };
  writingChecks = import (remote-zettel-runtime + /nix/work-writing-checks.nix) {
    inherit pkgs;
    baseCommit = "3689bb4c647704ca4c2d658b3e0e8a839eb6a116";
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/cloudflared.nix
    ../../modules/nixos/graphical.nix
    ../../modules/nixos/power-policy.nix
    ../../modules/nixos/printing.nix
    ../../modules/note-checkpoint-bridge.nix
    ../../modules/nixos/work-backup.nix
  ];

  networking.hostName = "deeley";

  services.fwupd.enable = true;
  services.cloudflare-warp.enable = true;

  services.zettel-checkpoint-bridge.enable = true;
  # Legacy Work backups remain administratively fenced after the v2 cutover.
  services.remote-zettel-work-backup.enable = false;

  # Retain the already commissioned immutable handoff and tools. These paths are
  # referenced by protected configuration outside the Nix store; do not GC them.
  system.extraDependencies = map retain [
    "/nix/store/7n4y6mw8vh407dbndnn8b4yhry84is4r-work-publication-commission"
    "/nix/store/dhzjkx6jp11qay7m8dmk1r0f1ljki6rz-work-publication-v2-provision"
    "/nix/store/4vs84cybhvrb236l607sy7xwn2kwp5fs-deeley-v2-public-handoff"
  ];
  environment.systemPackages = map retain [
    "/nix/store/7n4y6mw8vh407dbndnn8b4yhry84is4r-work-publication-commission"
    "/nix/store/dhzjkx6jp11qay7m8dmk1r0f1ljki6rz-work-publication-v2-provision"
    "/nix/store/sd03fp74ir23v57irgwdqx4f8f9qdxjc-work-candidate-ingest"
  ];

  users.users = {
    remote-zettel.uid = lib.mkForce 989;
    remote-zettel-work-host.uid = lib.mkForce 987;
    agent.uid = lib.mkForce 988;
    remote-zettel-work-importer.uid = 3202;
    remote-zettel-work-check.uid = 3203;
    remote-zettel-work-review.uid = 3204;
    remote-zettel-publisher = { isSystemUser = true; uid = 3205; group = "remote-zettel-publisher"; };
  };
  users.groups = {
    remote-zettel.gid = lib.mkForce 984;
    remote-zettel-work-host.gid = lib.mkForce 979;
    agent.gid = lib.mkForce 981;
    remote-zettel-work.gid = lib.mkForce 980;
    remote-zettel-work-bundle.gid = 3208;
    remote-zettel-work-check.gid = 3203;
    remote-zettel-work-review.gid = 3204;
    remote-zettel-publisher.gid = 3205;
  };

  services.remote-zettel = {
    enable = true;
    # Web code follows the ordinary flake input; enrolled runtime remains pinned.
    package = remote-zettel.packages.${pkgs.stdenv.hostPlatform.system}.default;
    publisherOutcomeService.package = remote-zettel-runtime.packages.${pkgs.stdenv.hostPlatform.system}.default;
    dataRoot = "/home/damon/Dropbox/000_zettelkasten";
    dataOwner = "damon";
    cloudflareAccess = {
      teamDomain = "late-thunder-9219.cloudflareaccess.com";
      audience = "68d97452fec8a3717afe57ce54949614ed41ea5f5cad9c52b68c988404d255a9";
      publicHostname = "zettel.ss-damon.com";
    };
    enablePiChat = true;
    noteCheckpointSocket = "/run/zettel-checkpoint/control.sock";
    enableDesktopCapture = true;
    # Fresh question-enabled epoch; the switch performs the declared v2 handoff.
    workPilot = {
      enable = true;
      enableExecution = true;
      enableContinuation = true;
      enableStructuredInput = true;
      package = remote-zettel-runtime.packages.${pkgs.stdenv.hostPlatform.system}.default;
      runtimeSource = remote-zettel-runtime.outPath;
      epoch = "task-lifecycle-v1";
      repository = "damon-sava-stanley/ssdamon-stories";
      coordinatorStatePath = "/var/lib/remote-zettel/work/task-lifecycle-v1/state.sqlite";
      documentsRoot = "/home/damon/Dropbox/agent-workspace-task-lifecycle-v1";
      baseCommit = "3689bb4c647704ca4c2d658b3e0e8a839eb6a116";
      checkCommand = writingChecks.worktree;
      candidateCheckCommand = writingChecks.candidate;
    };
    reusablePublication.enable = true;
    upgrade = {
      enable = true;
      repositoryId = "ssdamon-stories";
      previous = {
        epoch = "publication-v2";
        root = "/var/lib/remote-zettel-publication-v2";
        hostRoot = "/var/lib/remote-zettel-work-epoch-publication-v2-namespace-host";
        executorRoot = "/var/lib/remote-zettel-work-epoch-publication-v2-namespace-executor";
        sourceRepository = "/var/lib/remote-zettel-work-epoch-publication-v2-namespace-source";
        sourceStateDirectory = "/var/lib/remote-zettel-publication-v2/source-state";
        documentsRoot = "/home/damon/Dropbox/agent-workspace-publication-v2";
        coordinatorStatePath = "/var/lib/remote-zettel/work/publication-v2/state.sqlite";
        publisherStorePath = "/var/lib/remote-zettel-publication-v2/publisher/state.sqlite";
        ingestionDirectory = "/var/lib/remote-zettel-publication-v2/ingestion";
        approvalConfigurationFile = "/var/lib/remote-zettel-publication-v2/config/approval.json";
        publisherConfigurationFile = "/var/lib/remote-zettel-publication-v2/config/operator.json";
        writerDefinitions = previousWriters;
      };
    };
  };

  programs.fish.enable = true;

  # Recover the Framework touchpad when I2C HID stalls after suspend.
  powerManagement.resumeCommands = ''
    ${pkgs.kmod}/bin/modprobe -r i2c_hid_acpi
    ${pkgs.kmod}/bin/modprobe i2c_hid_acpi
  '';

  users.users.damon = {
    # Keep the note-checkpoint user timer running without an interactive login.
    linger = true;
    isNormalUser = true;
    uid = 1000;
    description = "Damon";
    shell = pkgs.fish;
    extraGroups = [
      "dialout"
      "networkmanager"
      "keyd"
      "wheel"
    ];
  };

  # Keep this at the version used for the initial installation.
  system.stateVersion = "26.05";
}

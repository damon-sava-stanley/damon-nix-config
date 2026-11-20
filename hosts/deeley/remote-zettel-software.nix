# Canonical enrollment; the operator helper derives a preparation-only variant.
{ config, lib, pkgs, remote-zettel-software, remote-zettel-software-policy, ... }:
{
  # NixOS 26.05 hardcodes this exact list in stage2ServiceConfig.
  # Expose it for the enrolled module's strict final-unit PATH verification.
  options.systemd.defaultPath = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    readOnly = true;
    default = [ pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused config.systemd.package ];
  };
  imports = [ ./remote-zettel-software-source.nix ];
  config.services.remote-zettel.repositoryInstances.remote-zettel = {
    enable = true;
    enableExecution = true;
    repository = "damon-sava-stanley/remote-zettel";
    baseCommit = "15edcc27575cbd703aa6c49853d759dcc81da4e4";
    sourceRepository = "/var/lib/remote-zettel-software-source/sources/software-v1/source";
    baseCommitFile = "/var/lib/remote-zettel-software-source-state/base";
    package = remote-zettel-software.packages.${pkgs.stdenv.hostPlatform.system}.default;
    runtimeSource = remote-zettel-software-policy.outPath;
    trustedSource = remote-zettel-software.outPath;
    npmDepsHash = "sha256-UXW2sL+XdNuo+pUhqzczvubdRyc3i8bKLRvGq5r/U4Q=";
    identities = {
      host = { uid = 3301; gid = 3301; };
      executor = { uid = 3302; gid = 3302; };
      check = { uid = 3303; gid = 3303; };
      review = { uid = 3304; gid = 3304; };
      bridge.gid = 3305;
    };
  };
}

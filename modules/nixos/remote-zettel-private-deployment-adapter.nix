# Independently pinned private-source adapter, with credentials only for prefetch.
{ pkgs, runtimeSource, buildFile, sshConfigurationFile, target, repository
, sourceUrl ? "https://github.com/${repository}.git"
, service ? "remote-zettel.service", healthPort ? 3210, healthTimeoutSeconds ? 30 }:
let
  file = toString buildFile;
  root = builtins.match "(/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._=-]+)(/.*)?" file;
  retainedFile = if root == null || builtins.getContext file != {} then file else
    builtins.appendContext file { "${builtins.head root}" = { path = true; }; };
  configuration = pkgs.writeText "remote-zettel-private-deployment-adapter.json" (builtins.toJSON {
    version = 1; inherit target repository service healthPort healthTimeoutSeconds;
    inherit sourceUrl;
    buildFile = retainedFile;
    stateDirectory = "/var/lib/remote-zettel-self-deployment/nixos-generations";
    nix = "${pkgs.nix}/bin/nix"; nixEnv = "${pkgs.nix}/bin/nix-env";
    nixStore = "${pkgs.nix}/bin/nix-store"; git = "${pkgs.git}/bin/git";
    systemctl = "${pkgs.systemd}/bin/systemctl";
  });
  package = pkgs.writeShellScriptBin "remote-zettel-private-nixos-adapter" ''
  exec ${pkgs.python3}/bin/python3 -I -B ${../../scripts/remote-zettel-private-deployment.py} \
    ${configuration} ${runtimeSource}/scripts/work-deployment-controller.py \
    ${runtimeSource}/scripts/nixos-deployment-adapter.py ${sshConfigurationFile} "$@"
'';
in package // { inherit configuration; }

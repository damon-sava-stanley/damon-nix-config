# Run after capturing inputs.nix and captured-sources.json. Retain the entire graph,
# so restricted evaluation can traverse only these declared store dependencies.
{ pkgs }:
let
  sources = builtins.fromJSON (builtins.readFile ./captured-sources.json);
  retain = path: builtins.appendContext path { "${path}" = { path = true; }; };
in pkgs.runCommand "deeley-trusted-deployment-host" {
  capturedSources = map retain sources;
} ''
  mkdir "$out"
  cp ${./build.nix} "$out/build.nix"
  cp ${./inputs.nix} "$out/inputs.nix"
  cp ${./resolved-flake.nix} "$out/resolved-flake.nix"
''

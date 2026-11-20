# Evaluate the operator-captured lock graph using existing store sources only.
# No fetchTree/getFlake, registries, candidate flakes, or evaluation-time URLs.
{ graph, rootName }:
let
  resolve = value: if builtins.isList value
    then builtins.foldl' (flake: name: flake.inputs.${name}) nodes.${rootName} value
    else nodes.${value};
  nodes = builtins.mapAttrs (name: node:
    let
      sourceInfo = node.sourceInfo;
      inputs = builtins.mapAttrs (_: resolve) (node.inputs or {});
      outputs = (import (sourceInfo.outPath + "/flake.nix")).outputs (inputs // { self = result; });
      result = outputs // sourceInfo // { inherit sourceInfo inputs outputs; _type = "flake"; };
    in if node.flake or true then result else sourceInfo
  ) graph;
in nodes.${rootName}

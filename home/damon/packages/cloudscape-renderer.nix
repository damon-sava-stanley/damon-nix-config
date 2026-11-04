{ papertoy, system }:

papertoy.packages.${system}.default.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ../cloudscape/papertoy-palette.patch
    ../cloudscape/papertoy-viewport.patch
  ];
  postPatch = (old.postPatch or "") + ''
    cp ${../cloudscape/palette.zig} src/palette.zig
  '';
  postBuild = (old.postBuild or "") + ''
    zig test src/palette.zig
  '';
})

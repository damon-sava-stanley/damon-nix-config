{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  installShellFiles,
  nodejs,
  xdg-utils,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "evenhub-cli";
  version = "0.2.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@evenrealities/evenhub-cli/-/evenhub-cli-${finalAttrs.version}.tgz";
    hash = "sha256-NL6gNag/GxclPmns5RYaDG8zZMVamGKiZn5f5DS5nbg=";
  };

  nativeBuildInputs = [
    makeWrapper
    installShellFiles
  ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/evenhub-cli"
    cp -r main.js package.json ehpk LICENSE "$out/lib/evenhub-cli/"
    makeWrapper ${lib.getExe nodejs} "$out/bin/evenhub" \
      --add-flags "$out/lib/evenhub-cli/main.js" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}
    ln -s evenhub "$out/bin/eh"

    installShellCompletion --bash --name evenhub completion/evenhub.sh
    installShellCompletion --zsh completion/_evenhub
    installShellCompletion --fish completion/evenhub.fish
    echo 'complete -c eh -w evenhub' > "$out/share/fish/vendor_completions.d/eh.fish"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/evenhub" --version)" = "${finalAttrs.version}"
    test "$("$out/bin/eh" --version)" = "${finalAttrs.version}"
    "$out/bin/evenhub" pack --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "CLI for Even Hub app development, packaging and distribution";
    homepage = "https://hub.evenrealities.com/docs/cli/index";
    # Upstream permits installing the published package to build and submit apps.
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    platforms = lib.platforms.all;
    mainProgram = "evenhub";
  };
})

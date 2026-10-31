{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  SDL2,
}:

stdenv.mkDerivation {
  pname = "flying-toasters";
  version = "0-unstable-578f659";

  src = fetchFromGitHub {
    owner = "marcusgreenwood";
    repo = "flying-toasters-wayland";
    rev = "578f659dc327e9ceb67cd9e010916eec954454be";
    hash = "sha256-AO/YxoHEoYKB0wbNHe6UbIWeLMT/S6T5vBEk81F6hIQ=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ SDL2 ];
  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/flying-toasters "$out/bin/flying-toasters"
    runHook postInstall
  '';

  meta = {
    description = "After Dark Flying Toasters recreation using SDL2";
    homepage = "https://github.com/marcusgreenwood/flying-toasters-wayland";
    platforms = lib.platforms.linux;
    mainProgram = "flying-toasters";
  };
}

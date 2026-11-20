{ pkgs, targetConfig }:
let
  app = "${targetConfig.services.remote-zettel.selfDeployment.automatic.package}/lib/remote-zettel";
  fixture = pkgs.runCommand "app-release-source-fixture" { nativeBuildInputs = [ pkgs.git pkgs.python3 ]; } ''
    export HOME="$TMPDIR" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    git init -q --initial-branch=main repo
    cd repo
    git config user.name Fixture
    git config user.email fixture@example.invalid
    printf 'first\n' > README
    git add README
    git commit -qm first
    old=$(git rev-parse HEAD)
    mkdir -p "$out/pack"
    cp -R . "$out/source"
    printf 'second\n' >> README
    git commit -qam second
    new=$(git rev-parse HEAD)
    printf '%s\n^%s\n' "$new" "$old" | git pack-objects --stdout --revs > "$out/pack/objects.pack"
    packid=$(git index-pack --index-version=2 -o "$out/pack/objects.idx" "$out/pack/objects.pack")
    python3 - "$out" "$old" "$new" "$packid" <<'PY'
    import pathlib,sys,json,hashlib
    root=pathlib.Path(sys.argv[1]); v=dict(oldBase=sys.argv[2],newBase=sys.argv[3],packId=sys.argv[4])
    for suffix in ['pack','idx']:
      raw=(root/'pack'/('objects.'+suffix)).read_bytes(); v[suffix]=dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
    (root/'manifest.json').write_text(json.dumps(v))
    PY
  '';
in pkgs.testers.runNixOSTest {
  name = "app-release-first-source-advance";
  nodes.machine = {
    system.stateVersion = "26.05";
    virtualisation.memorySize = 1024;
    system.extraDependencies = [ targetConfig.system.build.toplevel ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit('multi-user.target')
    machine.succeed('install -d -m 700 /var/lib/release-tests/tests /var/lib/release-tests/scripts')
    machine.succeed('cp ${./app-release-test.py} /var/lib/release-tests/tests/app-release-test.py')
    machine.succeed('cp ${../scripts/start-app-release-test.py} /var/lib/release-tests/scripts/start-app-release-test.py')
    machine.succeed('cp ${../scripts/remote-zettel-publication-bootstrap.py} /var/lib/release-tests/scripts/remote-zettel-publication-bootstrap.py')
    machine.succeed('RELEASE_FIXTURE=${fixture} RELEASE_APPLICATION=${app} RELEASE_NODE=${pkgs.nodejs_24}/bin/node ${pkgs.python3}/bin/python3 -I /var/lib/release-tests/tests/app-release-test.py', timeout=90)
  '';
}

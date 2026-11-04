{
  pkgs,
  cloudscapeRenderer,
  homeConfig,
}:

assert !(homeConfig.systemd.user.services ? awww-daemon);
assert
  homeConfig.systemd.user.services.cloudscape.Unit.After == [
    "niri.service"
    "waybar-theme-watcher.service"
  ];
assert builtins.elem "awww-daemon.service"
  homeConfig.systemd.user.services.cloudscape.Unit.Conflicts;
assert
  !(builtins.elem "awww-daemon.service" homeConfig.systemd.user.services.waybar-theme-watcher.Unit.Wants);

pkgs.runCommandLocal "cloudscape-test"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    # Ensure the patched renderer and its build-time Zig tests are also built.
    renderer = cloudscapeRenderer;
  }
  ''
    mkdir -p home/damon/cloudscape tests prototypes/cloudscape
    cp ${../home/damon/cloudscape/supervisor.py} home/damon/cloudscape/supervisor.py
    cp ${../home/damon/cloudscape/clouds.glsl} home/damon/cloudscape/clouds.glsl
    cp ${./cloudscape.py} tests/cloudscape.py
    cp ${../prototypes/cloudscape/index.html} prototypes/cloudscape/index.html
    cp ${../prototypes/cloudscape/try-papertoy.py} prototypes/cloudscape/try-papertoy.py
    cp ${../prototypes/cloudscape/test_trial.py} prototypes/cloudscape/test_trial.py
    python3 -B tests/cloudscape.py
    python3 -B -m unittest discover -s prototypes/cloudscape -p 'test_*.py'
    test -x "$renderer/bin/papertoy"
    touch "$out"
  ''

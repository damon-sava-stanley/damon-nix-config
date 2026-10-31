{ pkgs, lib, systemConfig }:
let
  home = systemConfig.home-manager.users.damon;
  service = home.systemd.user.services.zettel-checkpoint.Service;
  timer = home.systemd.user.timers.zettel-checkpoint;
  command = builtins.head service.ExecStart;
in
assert systemConfig.users.users.damon.linger;
assert lib.hasPrefix "/nix/store/" command;
assert lib.hasInfix "--state /home/damon/.local/state/zettel-checkpoint" command;
assert lib.hasInfix "--notes /home/damon/Dropbox/000_zettelkasten" command;
assert lib.hasInfix "git@github.com:damon-sava-stanley/remote-zettel-notes.git" command;
assert service.UMask == "0077";
assert timer.Timer.OnUnitInactiveSec == "2min";
assert timer.Install.WantedBy == [ "timers.target" ];
pkgs.runCommand "note-checkpoint-test" {
  nativeBuildInputs = [ pkgs.python3 pkgs.git ];
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME" source/scripts source/tests
  cp ${../home/damon/bin/note-checkpoint.py} source/scripts/note-checkpoint.py
  cp ${./note-checkpoint.py} source/tests/note-checkpoint-test.py
  python3 source/tests/note-checkpoint-test.py
  touch "$out"
''

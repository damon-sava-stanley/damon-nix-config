{ pkgs, lib, systemConfig }:
let
  home = systemConfig.home-manager.users.damon;
  service = home.systemd.user.services.zettel-checkpoint.Service;
  timer = home.systemd.user.timers.zettel-checkpoint;
  command = builtins.head service.ExecStart;
in
assert systemConfig.users.users.damon.linger;
assert systemConfig.services.zettel-checkpoint-bridge.enable;
assert systemConfig.systemd.services.remote-zettel.environment.NOTE_CHECKPOINT_SOCKET == "/run/zettel-checkpoint/control.sock";
assert systemConfig.systemd.services.remote-zettel.environment.NOTE_CHECKPOINT_ROOT == "/home/damon/Dropbox/000_zettelkasten";
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
  export NOTE_CHECKPOINT_SCRIPT=${../home/damon/bin/note-checkpoint.py}
  python3 ${./note-checkpoint.py}
  touch "$out"
''

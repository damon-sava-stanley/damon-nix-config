{ pkgs, lib, systemConfig }:
let
  service = systemConfig.systemd.services.zettel-checkpoint-bridge.serviceConfig;
in
assert service.User == "damon";
assert service.Group == "zettel-checkpoint";
assert service.ProtectHome == "tmpfs";
assert service.PrivateNetwork;
assert service.BindReadOnlyPaths == [ "/home/damon/Dropbox/000_zettelkasten" ];
assert service.BindPaths == [ "/home/damon/.local/state/zettel-checkpoint" ];
assert service.RestrictAddressFamilies == [ "AF_UNIX" ];
assert builtins.elem "zettel-checkpoint" systemConfig.users.users.remote-zettel.extraGroups;
assert lib.hasInfix "--allowed-user remote-zettel" service.ExecStart;
pkgs.runCommand "note-checkpoint-bridge-test" {
  nativeBuildInputs = [ pkgs.python3 pkgs.git ];
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  export NOTE_CHECKPOINT_SCRIPT=${../home/damon/bin/note-checkpoint.py}
  export NOTE_BRIDGE_SCRIPT=${../home/damon/bin/note-checkpoint-bridge.py}
  python3 ${./note-checkpoint-bridge.py}
  touch "$out"
''

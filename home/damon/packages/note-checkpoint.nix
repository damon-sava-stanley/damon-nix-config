{ pkgs }:
pkgs.writeShellApplication {
  name = "zettel-checkpoint";
  runtimeInputs = [ pkgs.python3 pkgs.git pkgs.openssh ];
  text = ''
    exec python3 ${../bin/note-checkpoint.py} "$@"
  '';
}

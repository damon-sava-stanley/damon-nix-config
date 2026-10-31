{ config, pkgs, lib, ... }:
let
  checkpoint = import ./packages/note-checkpoint.nix { inherit pkgs; };
  home = config.home.homeDirectory;
in
{
  # These two paths replace the previously hand-installed units on activation.
  xdg.configFile."systemd/user/zettel-checkpoint.service".force = true;
  xdg.configFile."systemd/user/zettel-checkpoint.timer".force = true;

  systemd.user.services.zettel-checkpoint = {
    Unit.Description = "Checkpoint text notes and push private Git backup";
    Service = {
      Type = "oneshot";
      UMask = "0077";
      ExecStart = "${checkpoint}/bin/zettel-checkpoint ${lib.escapeShellArgs [
        "--notes" "${home}/Dropbox/000_zettelkasten"
        "--state" "${config.xdg.stateHome}/zettel-checkpoint"
        "--remote" "git@github.com:damon-sava-stanley/remote-zettel-notes.git"
      ]}";
      TimeoutStartSec = "5min";
      NoNewPrivileges = true;
    };
  };
  systemd.user.timers.zettel-checkpoint = {
    Unit.Description = "Checkpoint changed notes every two minutes";
    Timer = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "2min";
      AccuracySec = "10s";
      Unit = "zettel-checkpoint.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}

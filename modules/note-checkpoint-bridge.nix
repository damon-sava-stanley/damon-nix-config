{ config, lib, pkgs, ... }:
let
  cfg = config.services.zettel-checkpoint-bridge;
  notes = "/home/damon/Dropbox/000_zettelkasten";
  state = "/home/damon/.local/state/zettel-checkpoint";
in
{
  options.services.zettel-checkpoint-bridge.enable = lib.mkEnableOption "private local note checkpoint bridge for Remote Zettel";

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.services.remote-zettel.enable;
      message = "The checkpoint bridge requires the Remote Zettel service identity";
    }];
    users.groups.zettel-checkpoint = {};
    users.users.remote-zettel.extraGroups = [ "zettel-checkpoint" ];
    systemd.services.zettel-checkpoint-bridge = {
      description = "Peer-authenticated local-only note checkpoints";
      wantedBy = [ "multi-user.target" ];
      # The existing timer/operator provisions the private backup state first.
      unitConfig.ConditionPathIsDirectory = [ notes state ];
      path = [ pkgs.git ];
      serviceConfig = {
        User = "damon";
        Group = "zettel-checkpoint";
        UMask = "0077";
        RuntimeDirectory = "zettel-checkpoint";
        RuntimeDirectoryMode = "0750";
        ExecStart = "${pkgs.python3}/bin/python3 ${../home/damon/bin/note-checkpoint-bridge.py} --socket /run/zettel-checkpoint/control.sock --allowed-user remote-zettel --notes ${notes} --state ${state} --remote git@github.com:damon-sava-stanley/remote-zettel-notes.git --checkpoint ${../home/damon/bin/note-checkpoint.py}";
        Restart = "on-failure";
        RestartSec = 3;
        KillMode = "control-group";
        TimeoutStopSec = 10;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "tmpfs";
        BindReadOnlyPaths = [ notes ];
        BindPaths = [ state ];
        PrivateTmp = true;
        PrivateNetwork = true;
        PrivateDevices = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        CapabilityBoundingSet = "";
        RestrictSUIDSGID = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
    };
  };
}

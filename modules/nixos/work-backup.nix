{ config, lib, pkgs, ... }:
let
  cfg = config.services.remote-zettel-work-backup;
  units = [ "remote-zettel-work-executor-supervisor.service" "remote-zettel-work-host.service"
    "remote-zettel-work-proxy.service" "remote-zettel.service" ];
  settings = pkgs.writeText "remote-zettel-work-backup.json" (builtins.toJSON {
    inherit units;
    webUnit = "remote-zettel.service";
    inherit (cfg) backupRoot destination documents owner;
    coordinator = "/var/lib/remote-zettel/work";
    host = "/var/lib/remote-zettel-work-host";
    executor = "/var/lib/remote-zettel-work-executor";
    source = "/var/lib/remote-zettel-work-source";
    scratch = "/var/lib/remote-zettel-work-documents";
  });
  command = "${pkgs.python3}/bin/python3 ${../../scripts/work-backup.py} --config ${settings}";
  safePath = p: builtins.match "/[A-Za-z0-9_./-]+" p != null && !(lib.hasInfix "/.." p) && !(lib.hasInfix "/./" p) && !(lib.hasInfix "//" p) && !(lib.hasSuffix "/" p);
in {
  options.services.remote-zettel-work-backup = {
    enable = lib.mkEnableOption "idle-only nightly Work snapshots and private Dropbox replication";
    owner = lib.mkOption { type = lib.types.str; default = "damon"; };
    documents = lib.mkOption { type = lib.types.str; default = "/home/damon/Dropbox/agent-workspace"; };
    destination = lib.mkOption { type = lib.types.str; default = "/home/damon/Dropbox/Backups/remote-zettel-work"; };
    backupRoot = lib.mkOption { type = lib.types.str; default = "/var/backups/remote-zettel-work"; };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      { assertion = builtins.hasAttr cfg.owner config.users.users; message = "Work backup owner must exist"; }
      { assertion = builtins.all safePath [ cfg.documents cfg.destination cfg.backupRoot ]; message = "Work backup paths must be safe absolute paths"; }
      { assertion = !(lib.hasPrefix (cfg.documents + "/") (cfg.destination + "/")) && !(lib.hasPrefix (cfg.destination + "/") (cfg.documents + "/")); message = "Backup destination must be separate from task documents"; }
    ];
    systemd.tmpfiles.rules = [
      "d ${cfg.backupRoot} 0700 root root -"
    ];
    systemd.services.remote-zettel-work-backup = {
      description = "Idle-only Work snapshot and private Dropbox replication";
      unitConfig.ConditionPathIsDirectory = [ cfg.documents cfg.destination ];
      path = [ pkgs.systemd pkgs.gnutar pkgs.gzip ];
      serviceConfig = {
        Type = "oneshot";
        User = "root"; Group = "root"; UMask = "0077";
        ExecStart = command;
        ExecStopPost = "${command} --recover";
        TimeoutStartSec = "1h"; TimeoutStopSec = "5min";
        KillMode = "control-group";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "tmpfs";
        BindReadOnlyPaths = [ cfg.documents ];
        BindPaths = [ cfg.destination ];
        ReadWritePaths = [ cfg.backupRoot cfg.destination ];
        PrivateTmp = true; PrivateDevices = true; PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        ProtectKernelTunables = true; ProtectKernelModules = true;
        ProtectControlGroups = true;
        # Root reads service-private stores and changes uid/gid for publication.
        CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" "CAP_DAC_OVERRIDE" "CAP_SETUID" "CAP_SETGID" ];
        AmbientCapabilities = [ "CAP_SETUID" "CAP_SETGID" ];
      };
    };
    systemd.timers.remote-zettel-work-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        AccuracySec = "1min";
        RandomizedDelaySec = 0;
        Persistent = false;
        Unit = "remote-zettel-work-backup.service";
      };
    };
  };
}

{ pkgs, lib, systemConfig }:
let
  service = systemConfig.systemd.services.remote-zettel-work-backup.serviceConfig;
  timer = systemConfig.systemd.timers.remote-zettel-work-backup.timerConfig;
in
assert service.User == "root";
assert service.UMask == "0077";
assert service.ProtectHome == "tmpfs";
assert service.PrivateNetwork;
assert service.RestrictAddressFamilies == [ "AF_UNIX" ];
assert lib.hasInfix "--recover" service.ExecStopPost;
assert timer.OnCalendar == "*-*-* 03:00:00";
assert timer.Persistent == false;
assert timer.RandomizedDelaySec == 0;
pkgs.runCommand "work-backup-tests" { nativeBuildInputs = [ pkgs.python3 pkgs.gnutar pkgs.gzip pkgs.acl ]; } ''
  cp -r ${../scripts} scripts
  mkdir tests
  cp ${./work-backup.py} tests/work-backup.py
  python3 tests/work-backup.py
  touch $out
''

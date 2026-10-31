{ pkgs, lib }:
let
  fixture = pkgs.writeText "work-backup-fixture.py" ''
    from pathlib import Path
    import sqlite3
    roots = ['/home/damon/Dropbox/agent-workspace', '/var/lib/remote-zettel/work',
      '/var/lib/remote-zettel-work-host', '/var/lib/remote-zettel-work-executor/operations',
      '/var/lib/remote-zettel-work-source', '/var/lib/remote-zettel-work-documents']
    for root in roots: Path(root).mkdir(parents=True, exist_ok=True)
    for file, table, column, value in [
      ('/var/lib/remote-zettel/work/state.sqlite','work_runs','status','needs-you'),
      ('/var/lib/remote-zettel-work-host/admission.sqlite','sequential_runs','status','terminal'),
      ('/var/lib/remote-zettel-work-executor/runs.sqlite','runs','phase','settled'),
      ('/var/lib/remote-zettel-work-executor/operations/runs.sqlite','runs','phase','settled')]:
      db=sqlite3.connect(file); db.execute(f'CREATE TABLE {table} ({column} TEXT)')
      db.execute(f'INSERT INTO {table} VALUES (?)',(value,)); db.commit(); db.close()
    for suffix in ["", '-wal', '-shm', '.ownership.sqlite']:
      Path('/var/lib/remote-zettel-work-host/credentials.sqlite'+suffix).write_text('SYNTHETIC SECRET')
    Path('/home/damon/Dropbox/agent-workspace/task.md').write_text('fixture task')
    Path('/var/lib/remote-zettel-work-executor/alias').symlink_to('/etc/shadow')
  '';
  tarProbe = pkgs.writeShellScriptBin "tar" ''
    if test -e /var/backups/remote-zettel-work/slow; then
      touch /var/backups/remote-zettel-work/entered
      ${pkgs.coreutils}/bin/sleep 120
    fi
    exec ${pkgs.gnutar}/bin/tar "$@"
  '';
  units = [ "remote-zettel" "remote-zettel-work-host" "remote-zettel-work-proxy" "remote-zettel-work-executor-supervisor" ];
in pkgs.testers.runNixOSTest {
  name = "work-backup";
  nodes.machine = { ... }: {
    imports = [ ../modules/nixos/work-backup.nix ];
    users.users.damon = { isNormalUser = true; uid = 1000; };
    services.remote-zettel-work-backup.enable = true;
    systemd.services = (lib.genAttrs units (_: {
      serviceConfig = { ExecStart = "${pkgs.coreutils}/bin/sleep infinity"; };
    })) // {
      remote-zettel-work-backup.path = lib.mkBefore [ tarProbe ];
    };
    environment.systemPackages = [ pkgs.python3 pkgs.acl ];
    virtualisation.memorySize = 1024;
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl stop remote-zettel-work-backup.timer")
    machine.succeed("python3 ${fixture}")
    machine.succeed("mkdir -p /home/damon/Dropbox/Backups/remote-zettel-work; chown -R damon:users /home/damon/Dropbox; chmod 700 /home/damon/Dropbox/Backups/remote-zettel-work")
    machine.succeed("setfacl -m u:damon:rw /home/damon/Dropbox/agent-workspace/task.md")
    units = "${lib.concatStringsSep " " (map (u: u + ".service") units)}"
    machine.succeed("systemctl start " + units)
    machine.succeed("systemctl start remote-zettel-work-backup.service || { cat /var/backups/remote-zettel-work/last-error.txt; exit 1; }")
    machine.succeed("systemctl is-active " + units)
    machine.succeed("python3 -c \"import json; s=json.load(open('/var/backups/remote-zettel-work/status.json')); assert s['result'].startswith('completed:')\"")
    machine.succeed("test $(find /home/damon/Dropbox/Backups/remote-zettel-work -name work.tar.gz | wc -l) = 1")
    machine.succeed("test $(stat -c %u /home/damon/Dropbox/Backups/remote-zettel-work/snapshot-*/work.tar.gz) = 1000")
    machine.succeed("cd /home/damon/Dropbox/Backups/remote-zettel-work/snapshot-* && sha256sum -c SHA256SUMS")
    machine.fail("tar -tzf /home/damon/Dropbox/Backups/remote-zettel-work/snapshot-*/work.tar.gz | grep credentials.sqlite")
    machine.succeed("python3 -c \"import glob,tarfile; t=tarfile.open(glob.glob('/var/backups/remote-zettel-work/snapshot-*/work.tar.gz')[0]); assert ':1000' in t.getmember('home/damon/Dropbox/agent-workspace/task.md').pax_headers['SCHILY.acl.access']\"")
    machine.succeed("python3 -c \"import glob,json; s=json.load(open(glob.glob('/var/backups/remote-zettel-work/snapshot-*/verification.json')[0])); assert s['sqliteDatabases']==4; assert s['retainedLinksNotFollowed']==1\"")
    # Busy: no restart or new snapshot.
    before = machine.succeed("systemctl show remote-zettel.service -p MainPID --value")
    machine.succeed("python3 -c \"import sqlite3; c=sqlite3.connect('/var/lib/remote-zettel/work/state.sqlite'); c.execute('UPDATE work_runs SET status=\\\"ready\\\"'); c.commit()\"")
    machine.succeed("systemctl start remote-zettel-work-backup.service")
    assert before == machine.succeed("systemctl show remote-zettel.service -p MainPID --value")
    machine.succeed("grep skipped-busy /var/backups/remote-zettel-work/status.json")
    machine.succeed("python3 -c \"import sqlite3; c=sqlite3.connect('/var/lib/remote-zettel/work/state.sqlite'); c.execute('UPDATE work_runs SET status=\\\"needs-you\\\"'); c.commit()\"")
    # Capture failure resumes services and preserves prior completed bundles.
    machine.succeed("mv /var/lib/remote-zettel-work-source /var/lib/source-away")
    machine.fail("systemctl start remote-zettel-work-backup.service")
    machine.succeed("systemctl is-active " + units)
    machine.succeed("test ! -e /var/backups/remote-zettel-work/recovery.json")
    machine.succeed("test $(find /home/damon/Dropbox/Backups/remote-zettel-work -name work.tar.gz | wc -l) = 1")
    machine.succeed("mv /var/lib/source-away /var/lib/remote-zettel-work-source")
    # SIGKILL bypasses finally; ExecStopPost recovers the recorded services.
    machine.succeed("touch /var/backups/remote-zettel-work/slow")
    machine.succeed("systemctl reset-failed remote-zettel-work-backup.service; systemctl start --no-block remote-zettel-work-backup.service")
    machine.wait_until_succeeds("test -e /var/backups/remote-zettel-work/entered")
    machine.succeed("systemctl kill --kill-whom=all --signal=SIGKILL remote-zettel-work-backup.service")
    machine.wait_until_succeeds("systemctl is-active " + units)
    machine.wait_until_succeeds("test ! -e /var/backups/remote-zettel-work/recovery.json")
    machine.wait_until_succeeds("grep interrupted /var/backups/remote-zettel-work/status.json")
  '';
}

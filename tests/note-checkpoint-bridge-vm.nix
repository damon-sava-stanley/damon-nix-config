{ pkgs, lib }:
let
  client = pkgs.writeText "checkpoint-client.py" ''
    import json, socket, sys
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
        peer.settimeout(130)
        peer.connect('/run/zettel-checkpoint/control.sock')
        request = {'version': 1, 'op': 'checkpoint'}
        if sys.argv[1] == 'invalid': request['command'] = 'touch /tmp/evil'
        try:
            peer.sendall((json.dumps(request) + '\n').encode())
            data = peer.recv(4096)
        except (ConnectionResetError, BrokenPipeError):
            data = b""
        if sys.argv[1] == 'ok':
            receipt = json.loads(data)
            assert receipt['ok'] is True
            assert receipt['root'] == '/home/damon/Dropbox/000_zettelkasten'
        else:
            assert not data
  '';
in
pkgs.testers.runNixOSTest {
  name = "note-checkpoint-bridge";
  nodes.machine = { lib, ... }: {
    imports = [ ../modules/note-checkpoint-bridge.nix ];
    # Minimal identity stub, not the web application. The real application's
    # unchanged mount policy is separately asserted in its module tests.
    options.services.remote-zettel.enable = lib.mkOption { type = lib.types.bool; default = true; };
    config = {
      services.zettel-checkpoint-bridge.enable = true;
      users.users.damon = { isNormalUser = true; uid = 1000; };
      users.users.remote-zettel = { isSystemUser = true; group = "remote-zettel"; };
      users.groups.remote-zettel = {};
      users.users.intruder = { isNormalUser = true; extraGroups = [ "zettel-checkpoint" ]; };
      systemd.services.zettel-checkpoint-bridge.wantedBy = lib.mkForce [];
      environment.systemPackages = [ pkgs.git pkgs.python3 pkgs.util-linux ];
    };
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("install -d -o damon -g users -m 0700 /home/damon/Dropbox/000_zettelkasten /home/damon/.ssh")
    machine.succeed("touch /home/damon/Dropbox/000_zettelkasten/.gitignore; echo before > /home/damon/Dropbox/000_zettelkasten/note.md; echo secret > /home/damon/.ssh/secret; chown -R damon:users /home/damon/Dropbox /home/damon/.ssh")
    machine.succeed("su -s ${pkgs.bash}/bin/bash damon -c 'mkdir -p -m 700 /home/damon/.local/state/zettel-checkpoint'")
    machine.succeed("systemctl start zettel-checkpoint-bridge")
    machine.wait_for_unit("zettel-checkpoint-bridge")
    machine.wait_until_succeeds("test -S /run/zettel-checkpoint/control.sock", timeout=30)
    machine.succeed("su -s ${pkgs.bash}/bin/bash remote-zettel -c '${pkgs.python3}/bin/python3 ${client} ok'")
    machine.succeed("su -s ${pkgs.bash}/bin/bash intruder -c '${pkgs.python3}/bin/python3 ${client} denied'")
    machine.succeed("su -s ${pkgs.bash}/bin/bash remote-zettel -c '${pkgs.python3}/bin/python3 ${client} invalid'")
    machine.fail("su -s ${pkgs.bash}/bin/bash remote-zettel -c 'cat /home/damon/.local/state/zettel-checkpoint/status.json'")
    machine.fail("su -s ${pkgs.bash}/bin/bash remote-zettel -c 'touch /run/zettel-checkpoint/replace'")
    pid = machine.succeed("systemctl show -p MainPID --value zettel-checkpoint-bridge").strip()
    machine.succeed(f"nsenter -t {pid} -m -- test ! -e /home/damon/.ssh/secret")
    machine.fail(f"nsenter -t {pid} -m -- touch /home/damon/Dropbox/000_zettelkasten/forbidden.md")
    machine.succeed("test ! -e /tmp/evil")
    machine.succeed("systemctl restart zettel-checkpoint-bridge")
    machine.wait_until_succeeds("su -s ${pkgs.bash}/bin/bash remote-zettel -c '${pkgs.python3}/bin/python3 ${client} ok'")
  '';
}

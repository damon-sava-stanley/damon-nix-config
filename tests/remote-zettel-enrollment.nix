{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "deeley-remote-zettel-enrollment-operator";
  nodes.machine = { ... }: {
    virtualisation.memorySize = 1024;
    users.groups.host.gid = 3301;
    users.users.host = { isSystemUser = true; uid = 3301; group = "host"; };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit('multi-user.target')
    machine.succeed('${pkgs.coreutils}/bin/env ENROLLMENT_MODULE=${../scripts/remote-zettel-enrollment.py} ${pkgs.python3}/bin/python3 ${./remote-zettel-enrollment.py}')
  '';
}

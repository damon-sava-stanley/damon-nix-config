{ pkgs, targetConfig }:
let
  targetSystem = targetConfig.system.build.toplevel;
  application = "${targetConfig.services.remote-zettel.selfDeployment.automatic.package}/lib/remote-zettel";
in pkgs.testers.runNixOSTest {
  name = "host-deployment-journal-resume";
  nodes.machine = { ... }: {
    system.stateVersion = "26.05";
    virtualisation.memorySize = 1024;
    # Explicitly retain the final controller/runtime closure for the root fixture.
    system.extraDependencies = [ targetSystem ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit('multi-user.target')
    machine.succeed('install -d -m 700 /var/lib/resume-tests /var/lib/resume-tests/tests /var/lib/resume-tests/scripts')
    machine.succeed('cp ${./resume-host-deployment.py} /var/lib/resume-tests/tests/resume-host-deployment.py')
    machine.succeed('cp ${../scripts/resume-host-deployment.py} /var/lib/resume-tests/scripts/resume-host-deployment.py')
    machine.succeed('RESUME_PREVIOUS_SCRIPTS=/nix/store/f92c9dbzqfgkcc8v7gwvr0w252p8szc9-work-host-policy-upgrade-scripts RESUME_NODE=${pkgs.nodejs_24}/bin/node RESUME_HELPER=${../scripts/resume-host-deployment.mjs} RESUME_APPLICATION=${application} RESUME_BRIDGE=${targetSystem}/etc/remote-zettel-self-deployment/bridge.json ${pkgs.python3}/bin/python3 -I /var/lib/resume-tests/tests/resume-host-deployment.py', timeout=90)
  '';
}

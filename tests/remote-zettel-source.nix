# Operator tool acceptance against a real protected source in a disposable VM.
{ pkgs, tool, baseCommit, sourceSnapshot ? null, runtimeSource ? null, sourcePath ? "/var/lib/remote-zettel-software-source/sources/software-v1/source", sourceState ? "/var/lib/remote-zettel-software-source-state", sourcePolicy ? "/var/lib/remote-zettel-software-source-policy/source-pin.json" }:
pkgs.testers.runNixOSTest {
  name = "work-software-source-commission";
  nodes.machine = { ... }: {
    virtualisation.memorySize = 1024;
    environment.systemPackages = [ tool pkgs.util-linux pkgs.git pkgs.python3 ];
    users.users.observer = { isSystemUser = true; group = "observer"; };
    users.groups.observer = {};
  };
  testScript = ''
    import json
    machine.start()
    machine.wait_for_unit('multi-user.target')
    command = 'remote-zettel-software-commission-source --commission'
    machine.fail('runuser -u observer -- ' + command)
    machine.fail('test -e ${sourcePath}')
    machine.fail('remote-zettel-software-commission-source --verify')
    machine.fail('test -e ${sourcePath}')
    machine.succeed(command)
    machine.succeed('remote-zettel-software-commission-source --verify')
    source = '${sourcePath}'
    state = '${sourceState}'
    pin = '${sourcePolicy}'
    assert machine.succeed('cat ' + state + '/base').strip() == '${baseCommit}'
    assert machine.succeed('cat ' + source + '/.git/refs/heads/publication-base').strip() == '${baseCommit}'
    assert machine.succeed('stat -c %u:%g:%a ' + source).strip() == '0:0:700'
    assert machine.succeed('stat -c %u:%g:%a ' + pin).strip() == '0:0:600'
    policy = json.loads(machine.succeed('cat ' + pin))
    assert policy['configuration'] == dict(repository=source, stateDirectory=state)
    assert len(policy['policyDigest']) == 64
    machine.fail('runuser -u observer -- cat ' + pin)
    machine.fail('runuser -u observer -- cat ' + source + '/.git/config')
    machine.succeed('runuser -u observer -- cat ' + state + '/base')
    retained = machine.succeed('sha256sum ' + pin + ' ' + state + '/base ' + source + '/.git/publication-source.ownership.sqlite')
    machine.fail(command)
    assert machine.succeed('sha256sum ' + pin + ' ' + state + '/base ' + source + '/.git/publication-source.ownership.sqlite') == retained
    ${pkgs.lib.optionalString (sourceSnapshot != null && runtimeSource != null) ''
    # The initial commit tracks a result symlink. The first Work candidate must
    # remove it, preserving the regular-files-only preparation policy.
    machine.succeed('cp -R ${sourceSnapshot} /var/lib/observer-checkout')
    machine.succeed('chmod -R u+rwX /var/lib/observer-checkout; chown -R observer:observer /var/lib/observer-checkout')
    machine.succeed('install -d -m 0700 -o observer -g observer /var/lib/observer-output')
    command = 'runuser -u observer -- ${pkgs.python3}/bin/python3 -I '
    receipt = json.loads(machine.succeed(command + '${runtimeSource}/scripts/capture-candidate.py /var/lib/observer-checkout ${baseCommit} /var/lib/observer-output/candidate.bundle'))
    machine.succeed('install -d -m 0700 -o observer -g observer /var/lib/observer-output/prepared')
    prepared = json.loads(machine.succeed(command + '${runtimeSource}/scripts/prepare-candidate.py /var/lib/observer-output/candidate.bundle /var/lib/observer-output/prepared --base ${baseCommit} --sha256 ' + receipt['sha256'] + ' --byte-length ' + str(receipt['byteLength']) + ' --candidate ' + receipt['candidateCommit'] + ' --tree ' + receipt['candidateTree'] + ' --git ${pkgs.git}/bin/git'))
    assert prepared['sourcePolicy'] == 'regular-files-v1'
    assert prepared['candidateCommit'] != '${baseCommit}'
    machine.fail('test -e /var/lib/observer-output/prepared/result')
    print('Full repository cleanup candidate verified and prepared:', prepared)
    machine.succeed('python3 -c ' + __import__('shlex').quote("import json,pathlib; p=pathlib.Path('" + pin + "'); v=json.loads(p.read_text()); v['policyDigest']='0'*64; p.write_text(json.dumps(v))"))
    machine.fail('remote-zettel-software-commission-source --verify')
    assert machine.succeed('cat ' + state + '/base').strip() == '${baseCommit}'
    ''}
  '';
}

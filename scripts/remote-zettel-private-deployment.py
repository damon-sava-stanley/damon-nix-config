"""Private-repository fetch for the independently pinned NixOS adapter.

Only the exact-source prefetch receives a fixed SSH command. Evaluation, builds,
activation and health use the existing adapter without credential environment.
"""
import ipaddress
import os
from pathlib import Path
import re
import runpy
import shlex
import stat
import subprocess
import sys


def private_key(path):
    if not isinstance(path, str) or not re.fullmatch(r'/var/lib/[A-Za-z0-9_./-]+', path) or os.path.normpath(path) != path:
        raise ValueError('Protected repository key required')
    value = Path(path)
    for parent in value.parents:
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise ValueError('Unprotected repository key ancestor')
    info = value.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != 0o400 or not 0 < info.st_size <= 16384):
        raise ValueError('Unsafe repository key')


def capture_ssh(c, ssh):
    connection = ssh['connection']
    host, user, address, port = (connection[k] for k in ('host', 'user', 'address', 'port'))
    if (not isinstance(host, str) or not re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)*', host)
            or not isinstance(user, str) or not re.fullmatch(r'[a-z_][a-z0-9_-]{0,63}', user)
            or type(port) is not int or not 1 <= port <= 65535
            or not isinstance(address, str) or str(ipaddress.ip_address(address)) != address
            or connection['repository'] != '/' + c['repository'] + '.git'
            or c['sourceUrl'] != 'https://' + host + connection['repository']):
        raise ValueError('Private fetch origin differs from enrolled repository')
    command = [ssh['ssh'], '-F', '/dev/null', '-o', 'BatchMode=yes', '-o', 'IdentityAgent=none',
        '-o', 'IdentitiesOnly=yes', '-o', 'PreferredAuthentications=publickey',
        '-o', 'StrictHostKeyChecking=yes', '-o', 'HostKeyAlias=publication-target',
        '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'UserKnownHostsFile=' + ssh['knownHosts'],
        '-o', 'Hostname=' + address, '-o', 'ConnectTimeout=15', '-i', ssh['credential']]
    return 'git+ssh://' + user + '@' + host + ':' + str(port) + connection['repository'], shlex.join(command)


def fetch_command(argv, tool_path, cache_path, ssh_command):
    # Match the original adapter's output/deadline/process-group contract.
    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, cwd='/', env={
            'PATH': tool_path, 'LANG': 'C.UTF-8', 'HOME': '/var/empty', 'NIX_PATH': '',
            'NIX_USER_CONF_FILES': '/dev/null', 'XDG_CACHE_HOME': cache_path,
            'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
            'GIT_TERMINAL_PROMPT': '0', 'GIT_SSH_COMMAND': ssh_command})
    try:
        output = bytearray()
        while chunk := os.read(process.stdout.fileno(), 16385):
            output.extend(chunk)
            if len(output) > 16384:
                raise ValueError('Private prefetch output budget exceeded')
        if process.wait() != 0:
            raise ValueError('Private source prefetch failed')
        return bytes(output)
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()


def private_adapter(base, c, contract, ssh, **kwargs):
    origin, ssh_command = capture_ssh(c, ssh)
    adapter = base['Adapter'](c, contract, command=lambda _: None, **kwargs)
    tools = str(Path(c['git']).parent)
    cache = str(adapter.state / 'cache')

    def execute(argv):
        prefetch = any(argv[i:i+2] == ['flake', 'prefetch'] for i in range(len(argv)-1))
        if prefetch:
            prefix = 'git+' + c['sourceUrl'] + '?rev='
            if argv[0] != c['nix'] or not argv[-1].startswith(prefix) or not re.fullmatch(r'[0-9a-f]{40}', argv[-1][len(prefix):]):
                raise ValueError('Exact enrolled private revision required')
            private_key(ssh['credential'])
            return fetch_command([*argv[:-1], origin + '?rev=' + argv[-1][len(prefix):]], tools, cache, ssh_command)
        return base['Adapter']._command(argv, tools, cache)

    adapter.command = execute
    return adapter


def main():
    if os.geteuid() != 0 or not sys.flags.isolated or len(sys.argv) != 6:
        raise ValueError('Root isolated private adapter invocation required')
    os.umask(0o077)
    configuration, controller, implementation, ssh_configuration, action = sys.argv[1:]
    contract = runpy.run_path(controller)
    # The wrapper and all these paths are fixed by the operator Nix package.
    for path in (configuration, controller, implementation, ssh_configuration):
        _, immutable = contract['resolve_store_path'](path)
        if not immutable:
            raise ValueError('Immutable private adapter inputs required')
    c = contract['protected_path'](configuration)
    ssh = contract['protected_path'](ssh_configuration)
    base = runpy.run_path(implementation)
    base['validate_configuration'](c, contract)
    for key in ('nix', 'nixEnv', 'nixStore', 'git', 'systemctl'):
        contract['protected_path'](c[key], executable=True)
    contract['protected_path'](ssh['ssh'], executable=True)
    for path in (ssh['knownHosts'], c['buildFile']):
        resolved, immutable = contract['resolve_store_path'](path)
        if not immutable or not stat.S_ISREG(os.stat(resolved).st_mode):
            raise ValueError('Immutable trust and host build files required')
    payload = contract['strict_json'](sys.stdin.buffer.read(4097))
    if len(contract['canonical'](payload)) > 4096:
        raise ValueError('Private adapter request budget exceeded')
    print(contract['canonical'](private_adapter(base, c, contract, ssh).dispatch(action, payload)).decode())


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Private NixOS adapter failed; inspect protected deployment state', file=sys.stderr)
        raise SystemExit(1)

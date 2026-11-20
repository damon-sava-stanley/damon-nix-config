import copy
import importlib.util
import io
import os
from pathlib import Path
import runpy
from types import SimpleNamespace
import stat
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT=Path(__file__).parents[1]
spec=importlib.util.spec_from_file_location('private_adapter',os.environ.get('REMOTE_ZETTEL_PRIVATE_ADAPTER',str(ROOT/'scripts/remote-zettel-private-deployment.py')))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
POLICY=Path(os.environ['REMOTE_ZETTEL_DEPLOYMENT_SOURCE'])
BASE=runpy.run_path(str(POLICY/'scripts/nixos-deployment-adapter.py'))
CONTRACT=runpy.run_path(str(POLICY/'scripts/work-deployment-controller.py'))
STORE='/nix/store/'+'a'*32
C=dict(version=1,target='deeley',repository='owner/app',sourceUrl='https://github.com/owner/app.git',buildFile=STORE+'-host/build.nix',stateDirectory='/var/lib/remote-zettel-self-deployment/nixos-generations',nix=STORE+'-nix/bin/nix',nixEnv=STORE+'-nix/bin/nix-env',nixStore=STORE+'-nix/bin/nix-store',git=STORE+'-git/bin/git',systemctl=STORE+'-systemd/bin/systemctl',service='remote-zettel.service',healthPort=3210,healthTimeoutSeconds=1)
SSH=dict(connection=dict(host='github.com',user='git',address='140.82.114.4',port=22,repository='/owner/app.git'),ssh=STORE+'-ssh/bin/ssh',knownHosts=STORE+'-trust',credential='/var/lib/private-publisher/identity')

class PrivateSourceTests(unittest.TestCase):
 def test_only_exact_enrolled_prefetch_gets_ssh(self):
  a=m.private_adapter(BASE,C,CONTRACT,SSH)
  argv=[C['nix'],'flake','prefetch','--json','git+https://github.com/owner/app.git?rev='+'b'*40]
  with patch.object(m,'private_key') as key,patch.object(m,'fetch_command',return_value=b'{}') as fetch,patch.object(BASE['Adapter'],'_command',return_value=b'build') as other:
   self.assertEqual(a.command(argv),b'{}')
   actual,tool,cache,command=fetch.call_args.args
   self.assertEqual(actual[-1],'git+ssh://git@github.com:22/owner/app.git?rev='+'b'*40)
   self.assertIn('IdentityAgent=none',command);self.assertIn('HostKeyAlias=publication-target',command)
   self.assertIn(SSH['credential'],command);key.assert_called_once_with(SSH['credential'])
   self.assertEqual(a.command([C['nix'],'build','--expr','fixture']),b'build')
   other.assert_called_once_with([C['nix'],'build','--expr','fixture'],tool,cache)
   self.assertEqual(fetch.call_count,1)
 def test_alternate_origin_and_revision_injection_are_denied(self):
  a=m.private_adapter(BASE,C,CONTRACT,SSH)
  for url in ['git+https://github.com/other/app.git?rev='+'b'*40,'git+https://github.com/owner/app.git?rev=main','git+https://github.com/owner/app.git?rev='+'b'*40+'&ref=evil']:
   with self.subTest(url=url),self.assertRaises(ValueError):a.command([C['nix'],'flake','prefetch',url])
 def test_enrolled_connection_must_match_repository(self):
  for key,value in [('repository','/other/app.git'),('address','github.com'),('host','github.com -oProxyCommand=evil'),('user','git;evil'),('port',True)]:
   ssh=copy.deepcopy(SSH);ssh['connection'][key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):m.capture_ssh(C,ssh)
 def test_key_requires_protected_ancestry_private_single_inode(self):
  good=SimpleNamespace(st_mode=stat.S_IFREG|0o400,st_uid=0,st_nlink=1,st_size=100)
  directory=SimpleNamespace(st_mode=stat.S_IFDIR|0o755,st_uid=0)
  def metadata(p):return good if str(p)==SSH['credential'] else directory
  with patch.object(Path,'lstat',metadata):m.private_key(SSH['credential'])
  for field,value in [('st_mode',stat.S_IFLNK|0o400),('st_mode',stat.S_IFREG|0o600),('st_uid',1000),('st_nlink',2),('st_size',0),('st_size',16385)]:
   bad=SimpleNamespace(**vars(good));setattr(bad,field,value)
   with self.subTest(field=field,value=value),patch.object(Path,'lstat',lambda p:bad if str(p)==SSH['credential'] else directory),self.assertRaises(ValueError):m.private_key(SSH['credential'])
  directory.st_mode|=0o020
  with patch.object(Path,'lstat',metadata),self.assertRaises(ValueError):m.private_key(SSH['credential'])
 def test_fetch_environment_excludes_inherited_credentials_and_bounds_output(self):
  process=Mock();process.stdout=Mock();process.stdout.fileno.return_value=10;process.wait.return_value=0;process.poll.return_value=0
  with patch.dict(os.environ,{'SHOULD_NOT_PROPAGATE':'secret'}),patch.object(m.subprocess,'Popen',return_value=process) as launch,patch.object(m.os,'read',side_effect=[b'{}',b'']):
   self.assertEqual(m.fetch_command(['nix','prefetch'],'/tools','/cache','/fixed/ssh'),b'{}')
   env=launch.call_args.kwargs['env'];self.assertNotIn('SHOULD_NOT_PROPAGATE',env);self.assertEqual(env['GIT_SSH_COMMAND'],'/fixed/ssh');self.assertEqual(env['GIT_TERMINAL_PROMPT'],'0')
  process.poll.return_value=None
  with patch.object(m.subprocess,'Popen',return_value=process),patch.object(m.os,'read',return_value=b'x'*16385),self.assertRaises(ValueError):m.fetch_command(['nix'],'/tools','/cache','/fixed/ssh')
  process.kill.assert_called_once()

if __name__=='__main__':unittest.main()

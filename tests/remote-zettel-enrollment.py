#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('operator_workflow', os.environ['ENROLLMENT_MODULE'])
workflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workflow)


@unittest.skipUnless(os.geteuid() == 0, 'Run in the root NixOS test VM')
class Enrollment(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='enroll-test-', dir='/var/lib'))
        self.addCleanup(shutil.rmtree, self.root)
        self.events = []
        self.failure = None
        self.catalog_pending = 0
        old = self.root / 'old';old.mkdir()
        prep = self.root / 'prepared';prep.mkdir()
        active = self.root / 'active';active.mkdir()
        current = self.root / 'current';current.symlink_to(old)
        selected = self.root / 'profile';selected.symlink_to(old)
        configuration = self.root / 'configuration.json';configuration.write_text(json.dumps({'policyDigest':'a'*64}))
        self.plan = {
            'policyDigest':'a'*64, 'operatorState':str(self.root/'operator'),
            'policyMarker':str(self.root/'policy'/'policy.json'), 'stateConfiguration':str(configuration),
            'credentials':str(self.root/'host'/'credentials.sqlite'), 'hostLedger':str(self.root/'host'/'admission.sqlite'),
            'hostUid':3301, 'hostGid':3301, 'hostUser':'host', 'hostUnit':'host.service',
            'preparedSystem':str(prep), 'executionSystem':str(active),
            'currentSystem':str(current), 'systemProfile':str(selected),
            'sourceRoots':[str(self.root/name) for name in ('source','source-state','source-policy')],
            'commissionSource':'source-tool', 'guard':'guard', 'login':'login', 'authProbe':'auth-probe',
            'nixEnv':'nix-env', 'systemctl':'systemctl', 'runuser':'runuser',
            'prepareUnit':'prepare.service', 'units':['host.service'],
            'webUser':'web', 'workCli':'work', 'controlSocket':'/unused/control.sock', 'repository':'owner/software',
        }
        self.addCleanup(patch.stopall)
        patch.object(workflow, 'run', side_effect=self.command).start()
        patch.object(workflow.subprocess, 'run', side_effect=self.status).start()
        patch.object(workflow.sys.stdin, 'isatty', return_value=True).start()
        patch.object(workflow.sys.stdout, 'isatty', return_value=True).start()

    def phase(self):
        return json.loads((Path(self.plan['operatorState'])/'state.json').read_text())['phase']

    def replace_link(self, path, target):
        p=Path(path);p.unlink();p.symlink_to(target)

    def credential(self, data=b'valid'):
        p=Path(self.plan['credentials']);p.write_bytes(data);p.chmod(0o600);os.chown(p,3301,3301)

    def status(self, command, **kwargs):
        if command[0]=='systemctl':
            code=0 if Path(self.plan['currentSystem']).resolve()==Path(self.plan['executionSystem']) else 3
        else:
            code=0 if Path(self.plan['credentials']).read_bytes()==b'valid' else 3
        return SimpleNamespace(returncode=code)

    def command(self, *command, capture=False):
        command=tuple(map(str,command));self.events.append(command)
        kind=command[0]
        if kind=='source-tool':
            roots=list(map(Path,self.plan['sourceRoots']))
            if command[1]=='--commission':
                for p in roots:p.mkdir()
            elif not all(p.is_dir() for p in roots):
                raise subprocess.CalledProcessError(1,command)
        elif kind=='nix-env':self.replace_link(self.plan['systemProfile'],command[-1])
        elif kind.endswith('/bin/switch-to-configuration'):
            target=str(Path(kind).parent.parent)
            if self.failure==target:raise subprocess.CalledProcessError(1,command)
            self.replace_link(self.plan['currentSystem'],target)
            if target==self.plan['preparedSystem']:
                marker=Path(self.plan['policyMarker']);marker.parent.mkdir(exist_ok=True)
                marker.write_text(json.dumps({'configuration':json.loads(Path(self.plan['stateConfiguration']).read_text()),'phase': 'preparing' if self.failure=='prepare-unit' else 'prepared'}));marker.chmod(0o600)
                host=Path(self.plan['credentials']).parent;host.mkdir(exist_ok=True);host.chmod(0o700);os.chown(host,3301,3301)
        elif kind=='systemctl' and 'prepare.service' in command and command[1]=='start':
            if self.failure=='prepare-unit':raise subprocess.CalledProcessError(1,command)
            marker=Path(self.plan['policyMarker']);value=json.loads(marker.read_text());value['phase']='prepared';marker.write_text(json.dumps(value))
        elif kind=='systemctl' and self.failure=='readiness' and 'host.service' in command:
            raise subprocess.CalledProcessError(1,command)
        elif kind=='login':
            if self.failure=='login':
                self.credential(b'')
                raise subprocess.CalledProcessError(1,command)
            self.credential()
            if self.failure=='login-after-save':raise subprocess.CalledProcessError(1,command)
        elif kind=='runuser':
            if command[-1]=='auth-probe':
                if Path(self.plan['credentials']).read_bytes()!=b'valid':raise subprocess.CalledProcessError(3,command)
            elif command[-1]=='board':return json.dumps({'repositories':['owner/stories','owner/software']})
            elif command[-1]=='catalog':
                if self.catalog_pending:
                    self.catalog_pending-=1;return '[]'
                return json.dumps([{'repository':'owner/software'}])
        return '' if capture else None

    def test_fresh_install_orders_commission_prepare_login_activate_readiness(self):
        workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'active')
        names=[c[0] for c in self.events]
        self.assertLess(names.index('source-tool'), names.index('login'))
        self.assertLess(names.index('login'), names.index(self.plan['executionSystem']+'/bin/switch-to-configuration'))
        self.assertEqual(self.events[-1][-1],'catalog')

    def test_preparation_failure_stops_before_login_and_catalog_and_resumes(self):
        self.failure=self.plan['preparedSystem']
        with self.assertRaises(subprocess.CalledProcessError):workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'source-ready')
        self.assertFalse(any(c[0]=='login' or c[-1]=='catalog' for c in self.events))
        self.failure=None;workflow.enroll(self.plan)
        self.assertEqual(self.events.count(('source-tool','--commission')),1)

    def test_cancelled_login_empty_store_is_retried_without_recommissioning(self):
        self.failure='login'
        with self.assertRaises(subprocess.CalledProcessError):workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'prepared')
        self.failure=None;workflow.enroll(self.plan)
        self.assertEqual(self.events.count(('source-tool','--commission')),1)
        self.assertEqual(self.events.count(('login',)),2)

    def test_failed_activation_preserves_auth_and_retry_skips_login(self):
        self.failure=self.plan['executionSystem']
        with self.assertRaises(subprocess.CalledProcessError):workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'authenticated')
        self.failure=None;workflow.enroll(self.plan)
        self.assertEqual(self.events.count(('login',)),1)

    def test_active_rerun_has_no_login_commission_or_profile_write(self):
        workflow.enroll(self.plan);self.events.clear();workflow.enroll(self.plan)
        self.assertFalse(any(c[0] in ('login','nix-env') or c==('source-tool','--commission') for c in self.events))
        self.assertEqual(self.phase(),'active')

    def test_missing_credentials_after_activation_are_not_replaced(self):
        workflow.enroll(self.plan);Path(self.plan['credentials']).unlink();self.events.clear()
        with self.assertRaisesRegex(RuntimeError,'missing'):workflow.enroll(self.plan)
        self.assertFalse(any(c[0] in ('login','nix-env') for c in self.events))

    def test_policy_drift_denies_before_any_external_effect(self):
        workflow.enroll(self.plan);self.plan['policyDigest']='b'*64;self.events.clear()
        with self.assertRaisesRegex(RuntimeError,'policy changed'):workflow.enroll(self.plan)
        self.assertEqual(self.events,[])

    def test_partial_source_is_retained_and_not_adopted(self):
        Path(self.plan['sourceRoots'][0]).mkdir()
        with self.assertRaises(subprocess.CalledProcessError):workflow.enroll(self.plan)
        self.assertNotIn(('source-tool','--commission'),self.events)
        self.assertTrue(Path(self.plan['sourceRoots'][0]).exists())

    def test_readiness_failure_is_not_recorded_as_active(self):
        self.failure='readiness'
        with self.assertRaises(subprocess.CalledProcessError):workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'authenticated')
        self.failure=None;workflow.enroll(self.plan)
        self.assertEqual(self.events.count(('login',)),1)
        self.assertEqual(self.phase(),'active')

    def test_symlinked_operator_journal_denies_without_effects(self):
        workflow.enroll(self.plan)
        journal=Path(self.plan['operatorState'])/'state.json'
        saved=journal.with_name('saved.json');journal.rename(saved);journal.symlink_to(saved)
        self.events.clear()
        with self.assertRaises(OSError):workflow.enroll(self.plan)
        self.assertEqual(self.events,[])

    def test_concurrent_main_is_rejected_and_lock_is_released(self):
        plan=dict(self.plan,hostname='test-host')
        config=self.root/'plan.json';config.write_text(json.dumps(plan))
        with patch.object(workflow.sys,'argv',['operator',str(config)]), patch.object(workflow.socket,'gethostname',return_value='test-host'):
            with patch.object(workflow,'enroll',side_effect=lambda _: workflow.main()):
                with self.assertRaisesRegex(RuntimeError,'Another enrollment'):workflow.main()
            with patch.object(workflow,'enroll') as call:
                workflow.main()
                call.assert_called_once()

    def test_interrupted_preparation_service_is_restarted_on_retry(self):
        self.failure='prepare-unit'
        with self.assertRaises(subprocess.CalledProcessError):workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'source-ready')
        self.failure=None;workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'active')
        self.assertEqual(self.events.count(('source-tool','--commission')),1)
        self.assertEqual(self.events.count(('systemctl','start','prepare.service')),2)

    def test_catalog_startup_delay_only_retries_observations(self):
        self.catalog_pending=1
        with patch.object(workflow.time,'sleep'):workflow.enroll(self.plan)
        self.assertEqual(sum(c[-1]=='catalog' for c in self.events),2)
        self.assertEqual(self.events.count(('login',)),1)
        self.assertEqual(self.phase(),'active')

    def test_catalog_timeout_does_not_mark_enrollment_active(self):
        self.catalog_pending=999
        with patch.object(workflow.time,'monotonic',side_effect=[0,31]):
            with self.assertRaisesRegex(RuntimeError,'readiness did not settle'):workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'authenticated')

    def test_saved_auth_after_interrupted_login_is_adopted_before_activation(self):
        self.failure='login-after-save'
        with self.assertRaises(subprocess.CalledProcessError):workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'prepared')
        self.failure=self.plan['executionSystem']
        with self.assertRaises(subprocess.CalledProcessError):workflow.enroll(self.plan)
        self.assertEqual(self.phase(),'authenticated')
        self.failure=None;workflow.enroll(self.plan)
        self.assertEqual(self.events.count(('login',)),1)
        self.assertEqual(self.phase(),'active')

    def test_noninteractive_initial_run_has_no_commission_or_switch(self):
        with patch.object(workflow.sys.stdin,'isatty',return_value=False):
            with self.assertRaisesRegex(RuntimeError,'interactive terminal'):workflow.enroll(self.plan)
        self.assertEqual(self.events,[])


if __name__=='__main__':unittest.main()

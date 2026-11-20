import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('reconcile', Path(__file__).parents[1] / 'scripts/reconcile-host-profile.py')
operator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(operator)


class Journals(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        config = dict(version=1, target='deeley', repository='owner/repo',
                      adapterCommand=str(Path(sys.executable).resolve()),
                      verifierCommand=str(Path(sys.executable).resolve()), commandTimeoutSeconds=10)
        configuration = self.root / 'configuration.json'
        configuration.write_text(json.dumps(config))
        self.policy = hashlib.sha256(json.dumps(config, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.bridge = dict(controllerStateDirectory=str(self.root),
            controllerConfigurationFile=str(configuration), deliveryStatePath=str(self.root / 'delivery.sqlite'),
            target='deeley', publication={'publisher': 'fixed'}, owner={'owner': 'fixed'})
        self.controller = sqlite3.connect(self.root / 'state.sqlite')
        self.delivery = sqlite3.connect(self.root / 'delivery.sqlite')
        self.addCleanup(self.controller.close)
        self.addCleanup(self.delivery.close)
        self.controller.executescript('CREATE TABLE policy(digest TEXT); CREATE TABLE deployments(id TEXT, record TEXT);')
        self.controller.execute('INSERT INTO policy VALUES (?)', (self.policy,))
        self.controller.commit()
        self.delivery.executescript('CREATE TABLE deployment_delivery_contract(singleton INTEGER, policy TEXT); '
                                   'CREATE TABLE deployment_delivery(request TEXT, acknowledgment TEXT);')
        contract = dict(version=1, target='deeley', controllerPolicyDigest=self.policy,
                        publication=self.bridge['publication'], owner=self.bridge['owner'])
        self.delivery.execute('INSERT INTO deployment_delivery_contract VALUES (1, ?)', (json.dumps(contract),))
        self.delivery.commit()
        patcher = patch.object(operator, 'protected', side_effect=lambda path, **_: Path(path))
        patcher.start()
        self.addCleanup(patcher.stop)

    def add_record(self, state='succeeded', ack=True):
        request = dict(deploymentId='deployment')
        record = dict(request=request, state=state, policyDigest=self.policy, generation='system', error=None, updatedAt='time')
        self.controller.execute('INSERT INTO deployments VALUES (?, ?)', ('deployment', json.dumps(record)))
        self.controller.commit()
        self.delivery.execute('INSERT INTO deployment_delivery VALUES (?, ?)',
                              (json.dumps(request), json.dumps(record) if ack else None))
        self.delivery.commit()

    def test_empty_commissioned_journals_are_settled(self):
        self.assertEqual(operator.journals(self.bridge), dict(controllerRecords=0, settledDeliveries=0))

    def test_matching_terminal_history_is_preserved(self):
        self.add_record()
        before = self.controller.execute('SELECT record FROM deployments').fetchall()
        self.assertEqual(operator.journals(self.bridge), dict(controllerRecords=1, settledDeliveries=1))
        self.assertEqual(self.controller.execute('SELECT record FROM deployments').fetchall(), before)

    def test_uncertain_deployments_refuse_reconciliation(self):
        for state in ('building', 'activating', 'activation-uncertain', 'health-failed', 'unknown'):
            with self.subTest(state=state):
                self.controller.execute('DELETE FROM deployments')
                self.delivery.execute('DELETE FROM deployment_delivery')
                self.add_record(state)
                with self.assertRaisesRegex(ValueError, 'Unsettled'):
                    operator.journals(self.bridge)

    def test_lost_controller_acknowledgment_refuses_reconciliation(self):
        self.add_record(ack=False)
        with self.assertRaisesRegex(ValueError, 'pending handoff'):
            operator.journals(self.bridge)

    def test_mismatched_acknowledgment_refuses_reconciliation(self):
        self.add_record()
        record = json.loads(self.delivery.execute('SELECT acknowledgment FROM deployment_delivery').fetchone()[0])
        record['generation'] = 'different-system'
        self.delivery.execute('UPDATE deployment_delivery SET acknowledgment=?', (json.dumps(record),))
        self.delivery.commit()
        with self.assertRaisesRegex(ValueError, 'terminal controller receipt'):
            operator.journals(self.bridge)

    def test_policy_drift_refuses_reconciliation(self):
        self.controller.execute("UPDATE policy SET digest='different'")
        self.controller.commit()
        with self.assertRaisesRegex(ValueError, 'running policy'):
            operator.journals(self.bridge)

    def test_busy_preflight_does_not_signal_or_change_profile(self):
        with patch.object(operator, 'selections', return_value={}), \
             patch.object(operator, 'bridge_state', return_value='active'), \
             patch.object(operator, 'journals', side_effect=ValueError('Unsettled')), \
             patch.object(operator, 'durable') as durable, patch.object(operator, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'Unsettled'):
                operator.reconcile()
            durable.assert_not_called()
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()

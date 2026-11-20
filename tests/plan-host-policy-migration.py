import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('planner', Path(__file__).parents[1] / 'scripts/plan-host-policy-migration.py')
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


def snapshot():
    enrollment = dict(frontendSocket='/run/frontend', profile=dict(repository='owner/repo',
        modelId='model', checkCommand='old-check', candidateCheckProfile='old-profile'))
    return dict(generation=dict(repository='owner/repo', identities={'host': 1},
                               shared={'state': '/state'}, bundle='bundle'),
        storiesEnrollment=enrollment, instances={'software': dict(enrollment=enrollment,
            state=dict(directories=[], policyDirectory='/policy', sourceRepository='/source', policyDigest='old'))},
        controller=dict(target='deeley', repository='owner/software', commandTimeoutSeconds=10), units={})


class Planner(unittest.TestCase):
    def test_plan_is_deterministic_and_does_not_authorize_activation(self):
        before = snapshot()
        after = copy.deepcopy(before)
        after['storiesEnrollment']['profile']['checkCommand'] = 'new-check'
        with patch.object(planner, 'snapshot', side_effect=[before, after, before, after]):
            first = planner.plan('old', 'new')
            second = planner.plan('old', 'new')
        self.assertEqual(first, second)
        self.assertFalse(first['activationAuthorized'])
        self.assertIn('/storiesEnrollment/profile/checkCommand', first['changes'])
        self.assertEqual(first['planDigest'], planner.digest({k: v for k, v in first.items() if k != 'planDigest'}))

    def test_unrelated_authority_changes_are_refused(self):
        for mutate in [
            lambda s: s['generation']['identities'].update(host=2),
            lambda s: s['generation']['shared'].update(state='/elsewhere'),
            lambda s: s['storiesEnrollment']['profile'].update(modelId='other'),
            lambda s: s['instances']['software']['state'].update(sourceRepository='/elsewhere'),
            lambda s: s['controller'].update(repository='different/repo'),
            lambda s: s['instances'].pop('software'),
        ]:
            before = snapshot()
            after = copy.deepcopy(before)
            mutate(after)
            with patch.object(planner, 'snapshot', side_effect=[before, after]):
                with self.assertRaises(ValueError):
                    planner.plan('old', 'new')


if __name__ == '__main__':
    unittest.main()

import asyncio
import importlib.util
import json
import os
from pathlib import Path
import time
import unittest
from unittest.mock import AsyncMock, Mock, patch

path = Path(os.environ.get('CODEX_HELPER', Path(__file__).resolve().parents[1] / 'home/damon/bin/waybar-codex.py'))
spec = importlib.util.spec_from_file_location('waybar_codex', path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class UsageTests(unittest.TestCase):
    def setUp(self):
        os.environ['TZ'] = 'UTC'
        time.tzset()

    def fixture(self, used=9, slot='primary'):
        return {'rateLimitsByLimitId': {'codex': {slot: {
            'usedPercent': used, 'windowDurationMins': 10080,
            'resetsAt': 1735912800}}}}

    def test_weekly_remaining_and_local_reset(self):
        for slot in ('primary', 'secondary'):
            result = helper.render(self.fixture(slot=slot))
            self.assertEqual(result['text'], '✨ 91%')
            self.assertEqual(result['percentage'], 91)
            self.assertEqual(result['tooltip'], 'Weekly allowance: 91% remaining\nResets Friday 02PM')
            self.assertEqual(result['class'], 'normal')

    def test_reset_uses_local_timezone_and_am(self):
        os.environ['TZ'] = 'EST5'
        time.tzset()
        self.assertTrue(helper.render(self.fixture())['tooltip'].endswith('Friday 09AM'))

    def test_legacy_bucket(self):
        data = self.fixture()
        self.assertEqual(helper.render({'rateLimits': data['rateLimitsByLimitId']['codex']})['percentage'], 91)

    def test_thresholds(self):
        for used, expected in ((80, 'warning'), (95, 'critical'), (100, 'critical')):
            self.assertEqual(helper.render(self.fixture(used))['class'], expected)

    def test_missing_or_invalid_weekly_data(self):
        for data in ({}, {'rateLimits': {'primary': {'windowDurationMins': 300}}}, self.fixture(-1), self.fixture(101), self.fixture('9')):
            with self.assertRaises(ValueError):
                helper.render(data)

    def test_unavailable_is_not_zero(self):
        result = helper.unavailable()
        self.assertEqual(result['text'], '✨ ?')
        self.assertNotIn('percentage', result)


class ProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def test_handshake_notifications_and_cleanup(self):
        process = Mock(returncode=None)
        process.stdin.drain = AsyncMock()
        process.wait = AsyncMock()
        process.stdout.readline = AsyncMock(side_effect=[
            b'{"id":1,"result":{}}\n',
            b'{"method":"account/updated","params":{}}\n',
            b'{"id":99,"result":{}}\n',
            b'{"id":2,"result":{"rateLimits":{}}}\n',
        ])
        with patch.object(helper.asyncio, 'create_subprocess_exec', AsyncMock(return_value=process)):
            self.assertEqual(await helper.fetch('codex'), {'rateLimits': {}})
        sent = [json.loads(call.args[0]) for call in process.stdin.write.call_args_list]
        self.assertEqual([msg['method'] for msg in sent], ['initialize', 'initialized', 'account/rateLimits/read'])
        process.terminate.assert_called_once()
        process.wait.assert_awaited_once()

    async def test_errors_and_eof_cleanup(self):
        for line in (b'{"id":1,"error":{"message":"unauthorized"}}\n', b''):
            process = Mock(returncode=None)
            process.stdin.drain = AsyncMock()
            process.wait = AsyncMock()
            process.stdout.readline = AsyncMock(return_value=line)
            with patch.object(helper.asyncio, 'create_subprocess_exec', AsyncMock(return_value=process)):
                with self.assertRaises(ValueError):
                    await helper.fetch('codex')
            process.terminate.assert_called_once()


if __name__ == '__main__':
    unittest.main()

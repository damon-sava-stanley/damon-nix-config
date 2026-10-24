"""Read Codex quota without starting a thread or handling credentials."""

import asyncio
from datetime import datetime
import json
import math
import sys


def render(data):
    buckets = data.get('rateLimitsByLimitId') or {}
    bucket = buckets.get('codex') or data.get('rateLimits') or {}
    if bucket.get('limitId') not in (None, 'codex'):
        raise ValueError('No Codex bucket')
    for slot in ('primary', 'secondary'):
        window = bucket.get(slot) or {}
        if window.get('windowDurationMins') != 10080:
            continue
        used = window.get('usedPercent')
        reset = window.get('resetsAt')
        if (type(used) not in (int, float) or not math.isfinite(used)
                or not 0 <= used <= 100 or type(reset) not in (int, float)):
            raise ValueError('Invalid quota')
        remaining = 100 - used
        display = f'{remaining:g}'
        local_reset = datetime.fromtimestamp(reset).strftime('%A %I%p')
        return {
            'text': f'✨ {display}%',
            'tooltip': f'Weekly allowance: {display}% remaining\nResets {local_reset}',
            'percentage': remaining,
            'class': 'critical' if remaining <= 5 else 'warning' if remaining <= 20 else 'normal',
        }
    raise ValueError('No weekly window')


def unavailable():
    return {'text': '✨ ?', 'tooltip': 'Codex weekly allowance unavailable', 'class': 'unavailable'}


async def fetch(codex):
    process = await asyncio.create_subprocess_exec(
        codex, 'app-server', '--stdio', cwd='/',
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )

    async def send(message):
        process.stdin.write((json.dumps(message) + '\n').encode())
        await process.stdin.drain()

    async def response(request_id):
        while True:
            line = await process.stdout.readline()
            if not line:
                raise ValueError('App server exited')
            message = json.loads(line)
            if message.get('id') == request_id:
                if 'error' in message:
                    raise ValueError('App server request failed')
                return message['result']

    try:
        async with asyncio.timeout(30):
            await send({'id': 1, 'method': 'initialize', 'params': {
                'clientInfo': {'name': 'waybar_codex_usage', 'version': '0.1.0'}}})
            await response(1)
            await send({'method': 'initialized', 'params': {}})
            await send({'id': 2, 'method': 'account/rateLimits/read'})
            return await response(2)
    finally:
        if process.returncode is None:
            try:
                process.terminate()
            except ProcessLookupError:
                pass
            try:
                await asyncio.wait_for(process.wait(), 5)
            except TimeoutError:
                process.kill()
                await process.wait()


def main():
    try:
        output = render(asyncio.run(fetch(sys.argv[1] if len(sys.argv) > 1 else 'codex')))
    except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError, TimeoutError):
        output = unavailable()
    print(json.dumps(output, ensure_ascii=False))


if __name__ == '__main__':
    main()

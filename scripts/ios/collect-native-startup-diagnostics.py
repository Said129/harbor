"""Preserve bounded simulator startup evidence even without a readable xcresult."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--simulator', required=True)
a = p.parse_args()
root = Path('ios/build/failed-native-render')
root.mkdir(parents=True, exist_ok=True)
test_log = Path('ios/build/logs/tests.log')
if test_log.is_file(): shutil.copyfile(test_log, root / 'tests.log')
report = []

def capture(name, command, timeout=30):
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout)
        (root / name).write_bytes(result.stdout[-1024 * 1024:])
        if result.stderr: (root / (name + '.stderr.txt')).write_bytes(result.stderr[-64 * 1024:])
        report.append(dict(name=name, exit_code=result.returncode, timed_out=False))
        return result.returncode == 0
    except subprocess.TimeoutExpired as error:
        (root / name).write_bytes((error.stdout or b'')[-1024 * 1024:])
        report.append(dict(name=name, exit_code=None, timed_out=True))
        return False

capture('devices.json', ['xcrun', 'simctl', 'list', 'devices', '--json'])
capture('processes.txt', ['ps', '-axo', 'pid,ppid,stat,etime,comm'])
capture('simulator-processes.txt', ['xcrun', 'simctl', 'spawn', a.simulator, 'launchctl', 'list'])
capture('startup-screen.txt', ['xcrun', 'simctl', 'io', a.simulator, 'screenshot', str(root / 'startup-screen.png')])
capture('startup-log.txt', ['xcrun', 'simctl', 'spawn', a.simulator, 'log', 'show', '--last', '10m', '--style', 'compact', '--predicate', 'process == "Harbor" OR process == "testmanagerd"'])
result = Path('ios/build/Tests.xcresult')
readable = False
if result.is_dir():
    capture('attachment-export.txt', ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(root / 'attachments')], timeout=60)
    readable = capture('test-result.json', ['xcrun', 'xcresulttool', 'get', 'object', '--legacy', '--format', 'json', '--path', str(result)], timeout=60)
    if readable:
        try: json.loads((root / 'test-result.json').read_text('utf-8'))
        except (ValueError, UnicodeError): readable = False
(root / 'startup-diagnostics.json').write_text(json.dumps(dict(captures=report, readable_result_bundle=readable, ipa_created=False), indent=2) + '\n')
print('Preserved simulator startup logs, screen where available, and any readable native test attachments; no IPA.')

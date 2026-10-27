"""Keep bounded system evidence after a failed owned simulator UI run; never retry it."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--device', required=True); p.add_argument('--label', required=True)
a = p.parse_args()
assert re.fullmatch(r'[A-Fa-f0-9-]{36}', a.device) and re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', a.label)
folder = Path('ios/build/canonical') / ('LaunchFailure-' + a.label); folder.mkdir(parents=True, exist_ok=True)
command = ['xcrun', 'simctl', 'spawn', a.device, 'log', 'show', '--last', '5m', '--style', 'compact', '--predicate',
    'process == "Harbor" OR (eventMessage CONTAINS "site.harbor.iphone" AND (process == "runningboardd" OR process == "launchd" OR process == "SpringBoard"))']
records = []
try:
    result = subprocess.run(command, capture_output=True, timeout=40)
    (folder / 'system-log.txt').write_bytes(result.stdout[-2 * 1_024 * 1_024:])
    (folder / 'system-log-stderr.txt').write_bytes(result.stderr[-64 * 1_024:])
    records.append(dict(log_returncode=result.returncode))
except subprocess.TimeoutExpired as error:
    (folder / 'system-log.txt').write_bytes((error.stdout or b'')[-2 * 1_024 * 1_024:]); records.append(dict(log_timed_out=True))
for source in sorted((Path.home() / 'Library/Logs/DiagnosticReports').glob('Harbor*.ips'), key=lambda value: value.stat().st_mtime, reverse=True)[:10]:
    if source.is_symlink() or source.stat().st_mtime < time.time() - 600 or source.stat().st_size > 2 * 1_024 * 1_024: continue
    content = source.read_bytes()
    if a.device.encode() not in content: continue
    (folder / source.name).write_bytes(content); records.append(dict(crash_report=source.name))
(folder / 'diagnostics.json').write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'], device=a.device, records=records, app_relaunched=False), indent=2) + '\n', 'utf-8')
print('Captured original launch failure evidence; no retry, reinstall or additional app launch.')

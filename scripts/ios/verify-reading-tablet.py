"""Retain approved phone reading checks while completing the interrupted iPad case."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
assert a.source == '5f5cda8f7dfd05d34cd94b275b96e7f7e93595ab'
subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', a.source], check=True)
paths = ['ios/Harbor', 'ios/project.yml', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'harbor-core', 'harbor-ios-bridge']
assert not subprocess.check_output(['git', 'diff', '--name-only', a.source, 'HEAD', '--', *paths]).strip(), 'Reassess any product or test change before preserving phone evidence'
guards = {}
for path in subprocess.check_output(['git', 'ls-files', *paths], text=True).splitlines():
    guards[path] = hashlib.sha256(Path(path).read_bytes()).hexdigest()

# Recheck the existing source/evidence chain, without executing any accepted tests.
chain = a.output.with_name('preserved-reading-final.json')
subprocess.run([sys.executable, 'scripts/ios/verify-reading-final.py', '--source', 'de34523b24386c26aa543221f6aafd9e6169f206', '--output', str(chain)], check=True)
prior = json.loads(chain.read_text('utf-8'))
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-reading-tablet'}
def get(path):
    with urllib.request.urlopen(urllib.request.Request(api + path + ('&' if '?' in path else '?') + 'observed=' + str(time.time_ns()), headers=headers), timeout=45) as r:
        return json.load(r)
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args): return None
run_id = 38746290857
run = get(f'/actions/runs/{run_id}')
assert run['status'] == 'completed' and run['conclusion'] == 'failure' and run['head_sha'] == a.source
jobs = get(f'/actions/runs/{run_id}/jobs?per_page=100')['jobs']
rows = []
for job in jobs:
    if job['conclusion'] == 'skipped': continue
    steps = {s['name']: s for s in job['steps']}
    for name in ['Preserve approved native and live providers before final reading review', 'Run bridge and model tests on iPhone simulator', 'Run native UI on the selected simulator']:
        assert steps[name]['conclusion'] == 'success', name
    assert steps['Verify the new reading shelves and PDF Manga on iPad']['conclusion'] == 'failure'
    request = urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers)
    try: response = urllib.request.build_opener(NoRedirect).open(request, timeout=45)
    except urllib.error.HTTPError as error:
        assert error.code == 302 and error.headers['Location'].startswith('https://')
        response = urllib.request.urlopen(error.headers['Location'], timeout=60)
    with response: log = response.read(50 * 1024 * 1024).decode('utf-8')
    assert "has timed out after 15 minutes" in log
    assert not re.search(r"Test Case .* (failed|skipped) ", log)
    assert 'Unbalanced calls to begin/end appearance transitions' not in log
    for line in log.splitlines():
        m = re.search(r"Test Case '-\[([^ ]+) ([^\]]+)\]' passed \(([^)]+)\)", line)
        if not m: continue
        stamp = datetime.fromisoformat(line.split(' ', 1)[0].replace('Z', '+00:00'))
        step = next(s for s in job['steps'] if s.get('started_at') and s.get('completed_at') and datetime.fromisoformat(s['started_at'].replace('Z', '+00:00')) <= stamp <= datetime.fromisoformat(s['completed_at'].replace('Z', '+00:00')))
        rows.append(dict(case=m[1] + '/' + m[2], result='passed', duration=m[3], source=a.source, run=run_id, device='iPad' if step['name'] == 'Verify the new reading shelves and PDF Manga on iPad' else 'iPhone', step=step['name']))
assert len(rows) == 5
native = [r for r in rows if r['case'] == 'HarborTests.ReadingUpdatesTests/testPDFMangaPagesCoversAndOwnerIsolation']
phone = [r for r in rows if r['case'].startswith('HarborUITests.ReadingNavigationTests/') and r['device'] == 'iPhone']
assert len(native) == 1 and len(phone) == 2
assert {r['case'] for r in phone} == {'HarborUITests.ReadingNavigationTests/testGutenbergSearchAndReadTheActualCoverAndText', 'HarborUITests.ReadingNavigationTests/testLocalShelvesSearchSortCoversAndPDFMangaReader'}
native = prior['preserved_native_executions'] + native
public = prior['preserved_public_executions']
assert len(native) == 9 and len(public) == 2
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'], preserved_source=a.source, preserved_run=run_id, preserved_native_executions=native, preserved_public_executions=public, preserved_phone_ui_executions=phone, preserved_executions=native + public + phone, identical_source_sha256=guards, failed_observations=prior['failed_observations'], superseded_visual_observation=prior['superseded_visual_observation'], interrupted_observation='Run 38746290857 exhausted its combined 15-minute iPad preparation/UI step. The UI case started but was interrupted before an outcome; it is not approved. The incomplete result bundle also prevented attachment export. Phone/native outcomes are retained from their successful steps and raw logs; their final images are unavailable.', pending='Only fresh iPad fixture preparation and the interrupted iPad shelf/PDF/rotation UI case execute, followed by device Release packaging.'), indent=2) + '\n', 'utf-8')
print('Retained nine native functional passes, two public provider passes and both phone reading UI passes. The interrupted iPad case remains pending.')

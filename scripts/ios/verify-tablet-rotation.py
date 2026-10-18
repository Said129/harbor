"""Preserve the compiled IPA while checking only its unresolved tablet rotation."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', required=True)
p.add_argument('--run', required=True, type=int)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
assert re.fullmatch(r'[0-9a-f]{40}', a.source)
subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', a.source], check=True)
paths = ['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']
changed = subprocess.check_output(['git', 'diff', '--name-only', a.source, 'HEAD', '--', *paths], text=True)
assert not changed.strip(), 'Application code and resources must match the compiled candidate exactly'
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
           'User-Agent': 'Harbor-tablet-rotation-review'}

def get(path):
    path += ('&' if '?' in path else '?') + 'observed=' + str(time.time_ns())
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response:
        return json.load(response)

run = get(f'/actions/runs/{a.run}')
assert run['status'] == 'completed' and run['conclusion'] == 'success' and run['head_sha'] == a.source
jobs = get(f'/actions/runs/{a.run}/jobs?per_page=100')['jobs']

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None

rows = []
for job in jobs:
    if job['conclusion'] == 'skipped':
        continue
    request = urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers)
    try:
        response = urllib.request.build_opener(NoRedirect).open(request, timeout=45)
    except urllib.error.HTTPError as error:
        assert error.code == 302 and error.headers['Location'].startswith('https://')
        response = urllib.request.urlopen(error.headers['Location'], timeout=60)
    with response:
        log = response.read(50 * 1024 * 1024).decode('utf-8')
    assert 'Unbalanced calls to begin/end appearance transitions' not in log
    for m in re.finditer(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(([^)]+)\)", log):
        rows.append({'case': m[1] + '/' + m[2], 'result': m[3], 'duration': m[4]})
expected = {
    'HarborTests.MangaArchiveTests/testActualCBZImagesUseNaturalOrderAndNeverExposeUnsafePaths',
    'HarborUITests.StableMobileNavigationTests/testContinueRemovalLanguagesAndReadingImportInNormalApp',
}
assert len(rows) == 2 and {r['case'] for r in rows} == expected and all(r['result'] == 'passed' for r in rows)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps({'source': os.environ['GITHUB_SHA'], 'application_source': a.source,
                               'compiled_run': a.run, 'preserved_executions': rows,
                               'production_identical': True,
                               'pending': 'ordinary tablet reading-help rotation only'}, indent=2) + '\n', 'utf-8')
print('Compiled candidate is unchanged. Approved cases are preserved; only tablet rotation runs.')

"""Keep approved phone/tablet evidence when only the remaining tablet UI runs."""
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
changed = set(subprocess.check_output(['git', 'diff', '--name-only', a.source, 'HEAD', '--',
                                      'ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge'], text=True).splitlines())
titles = ['ios/Harbor/Views/MangaView.swift', 'ios/Harbor/Views/MangaDetailView.swift', 'ios/Harbor/Views/MangaEditorialView.swift']
removed_notice = 'ios/Harbor/Licenses/QR-Ames-personal-use.txt'
assert changed == set(titles + ['ios/project.yml', removed_notice]), 'Only the reviewed font replacement may change production'
for path in titles + ['ios/project.yml']:
    before = subprocess.check_output(['git', 'show', a.source + ':' + path]).decode('utf-8')
    expected = before.replace('"QRAmesBeta-Regular"', '"Oswald-Regular"') if path in titles else before.replace('            QRAmesBeta.otf,\n', '')
    assert Path(path).read_text('utf-8') == expected, path
assert not Path(removed_notice).exists()
repo = os.environ['GITHUB_REPOSITORY']
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
           'User-Agent': 'Harbor-tablet-followup'}
api = 'https://api.github.com/repos/' + repo

def get(path):
    path += ('&' if '?' in path else '?') + 'observed=' + str(time.time_ns())
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response:
        return json.load(response)

run = get(f'/actions/runs/{a.run}')
assert run['status'] == 'completed' and run['head_sha'] == a.source
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
        assert error.code == 302
        location = error.headers['Location']
        assert location.startswith('https://')
        response = urllib.request.urlopen(location, timeout=60)  # Never forward repository credentials.
    with response:
        log = response.read(50 * 1024 * 1024).decode('utf-8')
    assert 'Unbalanced calls to begin/end appearance transitions' not in log
    for m in re.finditer(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(([^)]+)\)", log):
        rows.append({'case': m[1] + '/' + m[2], 'result': m[3], 'duration': m[4]})
expected = {
    'HarborTests.StableMobileTests/testRTLControlsAndLocalizedContinueWatchingLayout',
    'HarborTests.StableMobileTests/testContinueDismissalAndPrepareNormalAppUITapFixture',
    'HarborTests.StableMobileTests/testPDFReaderRestoresPageAfterLayoutAndNavigatesInBothDirections',
    'HarborTests.StableMobileTests/testTabletResizableReadingAndPlaybackOrientation',
    'HarborTests.VideoRenderingTests/testNativeRendererDisplaysDistinctColorsFrom8And10BitVideo',
    'HarborUITests.StableMobileNavigationTests/testContinueRemovalLanguagesAndReadingImportInNormalApp',
}
passed = [r for r in rows if r['result'] == 'passed']
assert len(passed) == 6 and {r['case'] for r in passed} == expected
ui = [r['result'] for r in rows if r['case'].startswith('HarborUITests.')]
assert ui == ['passed', 'failed'], 'Keep the actual successful phone and unsuccessful tablet UI observations'
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps({'source': os.environ['GITHUB_SHA'], 'preserved_source': a.source,
                               'preserved_run': a.run, 'preserved_executions': passed,
                               'pending': 'tablet UI and affected embedded Manga font',
                               'production_identical_except_reviewed_manga_font': True}, indent=2) + '\n', 'utf-8')
print('Preserved six approved phone/tablet executions; only tablet UI and the changed Manga font are pending.')

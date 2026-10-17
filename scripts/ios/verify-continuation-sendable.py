"""Preserve seven approved cases across one explicit concurrency annotation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
previous = '6a2f2a121749261485988822d3050e72ef47dd87'
source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
assert source == os.environ['GITHUB_SHA'] == os.environ['VALIDATED_SOURCE']
subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', previous], check=True)
roots = ['ios', 'harbor-core', 'harbor-ios-bridge']
changed = subprocess.check_output(['git', 'diff', '--name-only', previous, 'HEAD', '--', *roots], text=True).splitlines()
path = 'ios/Harbor/ViewModels/AppModel.swift'
assert changed == [path], 'Changes beyond the reviewed annotation require affected tests'

def blob(ref, name):
    return subprocess.check_output(['git', 'show', ref + ':' + name])

before, after = blob(previous, path), blob('HEAD', path)
old = b'group.addTask { @MainActor in'
new = b'group.addTask { @MainActor @Sendable in'
assert before.count(old) == 1 and after == before.replace(old, new, 1)
guards = {}
for name in subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', previous, '--', *roots], text=True).splitlines():
    if name != path:
        data = blob('HEAD', name)
        assert data == blob(previous, name), 'Changed application/test/shared source: ' + name
        guards[name] = hashlib.sha256(data).hexdigest()

headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-reviewed-concurrency-fix'}
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']

def get(url):
    with urllib.request.urlopen(urllib.request.Request(api + url, headers=headers), timeout=45) as response:
        return json.load(response)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, url):
        return None

def job_log(job):
    request = urllib.request.Request(api + f'/actions/jobs/{job}/logs', headers=headers)
    try:
        response = urllib.request.build_opener(NoRedirect).open(request, timeout=45)
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise
        url = error.headers['Location']
        assert url.startswith('https://')
        response = urllib.request.urlopen(url, timeout=60)
    with response:
        return response.read().decode('utf-8', errors='replace')

run = get('/actions/runs/39023116051')
assert run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] == 'success'
jobs = get('/actions/runs/39023116051/jobs?per_page=100')['jobs']
assert all(j['conclusion'] in ['success', 'skipped'] for j in jobs)
text = '\n'.join(job_log(j['id']) for j in jobs if j['conclusion'] == 'success')
assert not any(s in text for s in ['freed pointer', 'Restarting after unexpected exit', 'Unbalanced calls to begin/end appearance transitions'])
expected = {
    'HarborTests.ContinuationParityTests/testPlaybackAndContinueWatchingUseAbsoluteEpisodeNinetyNine',
    'HarborTests.ContinuationParityTests/testEpisodePresentationFallsBackWithoutInventingCoordinates',
    'HarborTests.ContinuationParityTests/testAnimeSelectionRecognizesIMDbAndKeepsDesktopShowsMembership',
    'HarborTests.ContinuationParityTests/testAnimeDetectionValidatesMappingAndCoalescesConcurrentChecks',
    'HarborTests.ContinuationParityTests/testPrepareOrdinaryContinuationUI',
    'HarborIntegrationTests.ContinuationParityLiveTests/testActualIMDbAnimeMappingAndEpisodeNinetyNinePresentation',
    'HarborUITests.ContinuationParityNavigationTests/testIMDbAnimeContinuesInAnimeAndShowsWithAbsoluteEpisodeNumber',
}
rows = [dict(name=m[1] + '/' + m[2], result=m[3], duration=m[4], run=39023116051, source=previous)
        for m in re.finditer(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(([^)]+)\)", text)]
started = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' started", text)
assert len(rows) == len(started) == 7 and {r['name'] for r in rows} == expected
assert all(r['result'] == 'passed' for r in rows)
proof = dict(application_source=source, workflow_source=os.environ['GITHUB_SHA'], previous_source=previous,
             compiler_annotation_only=True, reuse_authorized=True, complete=True, pending_ui=[],
             approved_results={r['name']: r for r in rows}, actual_executions_this_run=0,
             runs=[{k: run[k] for k in ['id', 'head_sha', 'conclusion', 'html_url', 'created_at']}],
             unchanged_guards_sha256=guards, reviewed_change={'path': path, 'before_sha256': hashlib.sha256(before).hexdigest(), 'after_sha256': hashlib.sha256(after).hexdigest(), 'change': 'Explicit @Sendable on the existing @MainActor closure; no scheduling, control flow, data or test changes.'},
             original_evidence_sha256='495cd32c4419c6855ddb238bdf79af30e423c5f922f28a8643bbb71e4ea62b69',
             physical_device_validation=False, full_desktop_parity_complete=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Preserved all seven passing cases and exact application/test blobs across one @Sendable annotation. Apple compilation must still pass.')

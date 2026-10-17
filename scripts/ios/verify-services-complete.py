"""Compose both new service source slices against the actually approved setup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--working-tree', action='store_true')
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
assert not (a.working_tree and os.environ.get('GITHUB_ACTIONS'))
previous = os.environ.get('HARBOR_PREVIOUS_SOURCE') or 'e9592c4b18eaea6698a7f5dac5de02a0822fd4b2'
intermediate = '9a68eb118f6304301d7a96560f2b9409897d0f87'
assert re.fullmatch('[a-f0-9]{40}', previous)
a.output.parent.mkdir(parents=True, exist_ok=True)
source = os.environ.get('GITHUB_SHA')
first = a.output.with_name('preserved-service-source-slice.json')
second = a.output.with_name('preserved-streaming-source-slice.json')
env = dict(os.environ, HARBOR_PREVIOUS_SOURCE=previous, HARBOR_CURRENT_SOURCE=intermediate, GITHUB_SHA=intermediate)
subprocess.run([sys.executable, 'scripts/ios/verify-service-browser.py', '--source-review-only', '--output', str(first)], env=env, check=True)
env = dict(os.environ, HARBOR_PREVIOUS_SOURCE=intermediate, HARBOR_CURRENT_SOURCE='HEAD')
command = [sys.executable, 'scripts/ios/verify-streaming-sync.py', '--source-review-only', '--output', str(second)]
if a.working_tree: command.append('--working-tree')
subprocess.run(command, env=env, check=True)
slices = [json.loads(path.read_text('utf-8')) for path in [first, second]]
assert all(value['prior_evidence_verified'] is False and value['intermediate_source_review_only'] is True for value in slices)
assert slices[0]['source'] == intermediate and slices[0]['previous_source'] == previous
assert slices[1]['previous_source'] == intermediate
proof = dict(source=source, previous_source=previous, scope='services-complete', local_source_review_only=a.working_tree,
             prior_evidence_verified=False, intermediate_source_review_only=True, source_slices=slices,
             expected_actual_executions=24, new_native_methods=18, affected_existing_native_methods=2,
             ui_methods=4, expected_new_images=10, required_recordings=['service-iphone.mp4', 'service-ipad.mp4'],
             ipa_created=False, physical_device_validation=False, complete_multi_profile_ui=False,
             full_desktop_parity_complete=False)
if not a.working_tree:
    api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-combined-service-validation'}
    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
    ids = os.environ['HARBOR_PREVIOUS_RUNS'].split(','); assert all(re.fullmatch('[0-9]+', value) for value in ids)
    runs = [get('/actions/runs/' + value) for value in ids]
    approved = [run for run in runs if run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] == 'success']
    assert len(approved) == 1, 'The setup baseline must have actually completed successfully'
    run = approved[0]
    job = next(job for job in get(f'/actions/runs/{run["id"]}/jobs?per_page=100')['jobs'] if job['name'] == 'Apple SDK / Swift / iPhone')
    assert job['conclusion'] == 'success'
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, file, code, message, response_headers, new_url): return None
    try: response = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers), timeout=45)
    except urllib.error.HTTPError as redirect:
        if redirect.code != 302: raise
        location = redirect.headers['Location']; assert urllib.parse.urlparse(location).scheme == 'https'
        response = urllib.request.urlopen(location, timeout=45)
    with response: data = response.read(32 * 1024 * 1024 + 1)
    assert len(data) <= 32 * 1024 * 1024
    expected = set()
    for suite, folder in [('OnboardingContentTests', 'HarborTests'), ('StreamingPreferencesTests', 'HarborTests'), ('OnboardingLiveTests', 'HarborIntegrationTests'), ('OnboardingNavigationTests', 'HarborUITests'), ('LanguageReferenceNavigationTests', 'HarborUITests'), ('SystemMaintenanceNavigationTests', 'HarborUITests')]:
        content = subprocess.check_output(['git', 'show', previous + ':ios/' + folder + '/' + suite + '.swift']).decode('utf-8')
        expected.update(folder + '.' + suite + '/' + name for name in re.findall(r'\bfunc (test\w+)\(', content))
    outcomes = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", data.decode('utf-8', errors='replace'))
    assert len(expected) == len(outcomes) == 16 and {row[0] + '/' + row[1] for row in outcomes} == expected and all(row[2] == 'passed' for row in outcomes)
    proof.update(prior_evidence_verified=True, preserved_setup_run=run['id'], preserved_actual_cases=sorted(expected), previous_job_log_sha256=hashlib.sha256(data).hexdigest(),
                 affected_existing_cases_revalidated=['HarborTests.StreamingPreferencesTests/testOwnerIsolationPersistenceAndFailedWritesKeepThePublishedSelection', 'HarborTests.StreamingPreferencesTests/testUnreadablePreferencesCannotBeOverwrittenByFallbackDefaults'])
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Both new service slices reviewed against the setup source; ' + ('Apple execution pending.' if a.working_tree else 'actual setup evidence preserved; 24 affected executions required.'))

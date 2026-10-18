"""Preserve 25 actual passes and run only four unfinished iPad journeys."""
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
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
baseline = '10de4bf90ade5d725b996670a042a678ef0ff298'
if subprocess.run(['git', 'cat-file', '-e', baseline + '^{commit}'], capture_output=True).returncode:
    subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', baseline], check=True)
roots = ['ios/Harbor', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
assert not subprocess.check_output(['git', 'diff', '--name-only', baseline, 'HEAD', '--', *roots], text=True).strip(), 'Application and tests must remain identical to the actually executed source'
subprocess.run([sys.executable, 'scripts/ios/verify-services-ui.py', '--output', str(a.output)], check=True)
proof = json.loads(a.output.read_text('utf-8'))
assert proof['prior_evidence_verified'] and proof['actual_prior_passes'] == 23
prior_run = 39145001255
assert str(prior_run) in os.environ['HARBOR_PREVIOUS_RUNS'].split(',')
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-tablet-only-review'}
def get(path):
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
run = get(f'/actions/runs/{prior_run}')
assert run['head_sha'] == baseline and run['status'] == 'completed' and run['conclusion'] == 'failure'
job = next(row for row in get(f'/actions/runs/{prior_run}/jobs?per_page=100')['jobs'] if row['name'] == 'Apple SDK / Swift / iPhone')
assert job['conclusion'] == 'failure'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, response_headers, new_url): return None
try:
    response = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers), timeout=45)
except urllib.error.HTTPError as redirect:
    if redirect.code != 302: raise
    location = redirect.headers['Location']; assert urllib.parse.urlparse(location).scheme == 'https'
    response = urllib.request.urlopen(location, timeout=45)
with response: data = response.read(32 * 1024 * 1024 + 1)
assert len(data) <= 32 * 1024 * 1024
text = data.decode('utf-8', errors='replace')
passed = {
    'HarborUITests.ServiceCatalogNavigationTests/testServiceIndexFiltersAndMetadataSetupWorkInTheIPhoneInterface',
    'HarborUITests.LanguageReferenceNavigationTests/testReferenceLanguagesSwitchInTheOrdinaryIPadSettings',
}
unfinished = 'HarborUITests.OnboardingNavigationTests/testTenStepSetupUsesRealControlsInTheIPadInterface'
rows = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", text)
assert len(rows) == 2 and {suite + '/' + name: result for suite, name, result in rows} == {case: 'passed' for case in passed}
starts = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' started\.", text)
assert len(starts) == 3 and {suite + '/' + name for suite, name in starts} == passed | {unfinished}
assert next(step for step in job['steps'] if step['name'] == 'Run native UI on the selected simulator')['conclusion'] == 'success'
assert next(step for step in job['steps'] if step['name'] == 'Run the full service browser on iPad')['conclusion'] == 'failure'
for name in ['Run bridge and model tests on iPhone simulator', 'Run real addon services on iPhone simulator', 'Package and verify unsigned iPhone IPA']:
    assert next(step for step in job['steps'] if step['name'] == name)['conclusion'] == 'skipped'
pending = set(proof['pending_ui_cases']) - passed
assert len(pending) == 4 and unfinished in pending
proof.update(scope='services-tablet', application_source=baseline, application_byte_identical=True,
    preserved_cases=sorted(set(proof['preserved_cases']) | passed), actual_prior_passes=25,
    pending_ui_cases=sorted(pending), expected_actual_executions=4,
    expected_new_images_minimum=16, optional_transient_images=1, required_recordings=['service-ipad.mp4'],
    latest_run=prior_run, latest_job_log_sha256=hashlib.sha256(data).hexdigest(),
    prior_unfinished_case=unfinished, prior_unfinished_case_counted_as_pass=False,
    note='The tablet step exhausted its 20-minute limit after two actual passes. Build/UI work now has a longer bound and separate result bundles; passed phone/language cases are not repeated. This validates the frozen service slice, not later application changes.')
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('25 actual passes retained. Four unfinished iPad journeys only. No IPA.')

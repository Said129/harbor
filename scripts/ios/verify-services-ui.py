"""Preserve 23 actual passes; execute only the failed phone route and five pending iPad routes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--working-tree', action='store_true')
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
assert not (a.working_tree and os.environ.get('GITHUB_ACTIONS'))
baseline = '8bcd1a004202b08fb2b97726a5e5d10ab8fa3ac8'
prior_run = 39073293767
assert os.environ.get('HARBOR_PREVIOUS_SOURCE', baseline) == baseline
source = os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()

def changed(roots):
    args = ['git', 'diff', '--name-only', baseline] + ([] if a.working_tree else ['HEAD']) + ['--', *roots]
    result = set(subprocess.check_output(args, text=True).splitlines())
    if a.working_tree:
        result.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *roots], text=True).splitlines())
    return result

assert not changed(['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']), 'The entire production application must remain byte-identical'
test = 'ios/HarborUITests/ServiceCatalogNavigationTests.swift'
assert changed(['ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests']) == {test}
old = subprocess.check_output(['git', 'show', baseline + ':' + test]).decode('utf-8')
before = '''        for _ in 0..<8 { if horror.isHittable { break }; categories.swipeLeft() }
        XCTAssertTrue(horror.isHittable); horror.tap(); XCTAssertTrue(horror.isSelected)'''
after = '''        app.buttons["service-category-menu"].tap()
        let horrorAction = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Terror", "service-category-horror")).firstMatch
        XCTAssertTrue(horrorAction.waitForExistence(timeout: 5)); horrorAction.tap()
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: horror)
        wait(for: [selected], timeout: 5)
        XCTAssertTrue(categories.frame.intersects(horror.frame))'''
assert old.count(before) == 1
current = Path(test).read_text('utf-8') if a.working_tree else subprocess.check_output(['git', 'show', 'HEAD:' + test]).decode('utf-8')
assert current == old.replace(before, after), 'Only the offscreen category automation route may change'

def cases(folder, suite):
    text = subprocess.check_output(['git', 'show', f'{baseline}:ios/{folder}/{suite}.swift']).decode('utf-8')
    return {folder + '.' + suite + '/' + name for name in re.findall(r'\bfunc (test\w+)\(', text)}

expected = cases('HarborTests', 'ServiceCatalogTests') | cases('HarborTests', 'StreamingSyncTests')
expected.update('HarborTests.StreamingPreferencesTests/' + name for name in [
    'testOwnerIsolationPersistenceAndFailedWritesKeepThePublishedSelection',
    'testUnreadablePreferencesCannotBeOverwrittenByFallbackDefaults'])
expected.update([
    'HarborIntegrationTests.OnboardingLiveTests/testNativeTasteSetupLoadsActualPublicTitlesWithCoversWithoutBundledKeys',
    'HarborUITests.OnboardingNavigationTests/testTenStepSetupUsesRealControlsInTheIPhoneInterface',
    'HarborUITests.StreamingSelectionNavigationTests/testOrdinaryIPhoneServiceSelectionSurvivesRelaunch'])
assert len(expected) == 23
failed = 'HarborUITests.ServiceCatalogNavigationTests/testServiceIndexFiltersAndMetadataSetupWorkInTheIPhoneInterface'
pending = cases('HarborUITests', 'ServiceCatalogNavigationTests') | {
    'HarborUITests.OnboardingNavigationTests/testTenStepSetupUsesRealControlsInTheIPadInterface',
    'HarborUITests.StreamingSelectionNavigationTests/testOrdinaryIPadServiceSelectionSurvivesRelaunch',
    'HarborUITests.LanguageReferenceNavigationTests/testReferenceLanguagesSwitchInTheOrdinaryIPadSettings',
    'HarborUITests.SystemMaintenanceNavigationTests/testStorageAndAboutWorkInTheOrdinaryIPadInterface'}
assert len(pending) == 6 and not (expected & pending)
proof = dict(source=source, previous_source=baseline, scope='services-ui', prior_run=prior_run,
             application_byte_identical=True, prior_evidence_verified=False,
             local_source_review_only=a.working_tree, preserved_cases=sorted(expected), pending_ui_cases=sorted(pending),
             expected_actual_executions=6, expected_new_images_minimum=23, optional_transient_images=1,
             required_recordings=['service-iphone.mp4', 'service-ipad.mp4'],
             ipa_created=False, full_desktop_parity_complete=False, physical_device_validation=False)
if not a.working_tree:
    assert str(prior_run) in os.environ['HARBOR_PREVIOUS_RUNS'].split(',')
    api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-service-ui-follow-up'}
    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response:
            return json.load(response)
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
    rows = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", text)
    assert len(rows) == 24 and len({suite + '/' + name for suite, name, _ in rows}) == 24
    outcomes = {suite + '/' + name: result for suite, name, result in rows}
    assert outcomes == dict({case: 'passed' for case in expected}, **{failed: 'failed'})
    starts = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' started\.", text)
    assert len(starts) == 24 and {suite + '/' + name for suite, name in starts} == set(outcomes)
    assert 'Activation point invalid and no suggested hit points based on element frame' in text
    for step_name in ['Run bridge and model tests on iPhone simulator', 'Run real addon services on iPhone simulator']:
        assert next(step for step in job['steps'] if step['name'] == step_name)['conclusion'] == 'success'
    assert next(step for step in job['steps'] if step['name'] == 'Run the full service browser on iPad')['conclusion'] == 'skipped'
    proof.update(prior_evidence_verified=True, prior_job_log_sha256=hashlib.sha256(data).hexdigest(),
                 previous_failure=failed, previous_failure_kind='offscreen-hittability-query-in-test',
                 actual_prior_passes=23, new_native_executions=0, new_public_service_executions=0)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Unchanged application verified; ' + ('prior execution review pending.' if a.working_tree else '23 actual passes preserved. Six pending UI routes only; no IPA.'))

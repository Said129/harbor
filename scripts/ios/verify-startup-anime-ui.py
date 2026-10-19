"""Preserve actual model/language passes before the remaining ordinary-device UI."""
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
from startup_anime_ui_plan import execution_plan

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--source-only', action='store_true', help='Inspect frozen source/selection only; does not approve prerequisites or dispatch')
a = p.parse_args()
application = 'c81bd5c8503e31f2bec973e70c2dfb23eedb4259'
native_source = '7ec9a586e571d2ee6c42accc0bfeb1e56aa95b24'
previous_ui = 'c6793804c5abf25538c24a826e5fa5e5b7aca40e'
old_source = '5efc1179df26a80c59b9b5cbf858b214335246e2'
for revision in [application, native_source, previous_ui, old_source]:
    if subprocess.run(['git', 'cat-file', '-e', revision + '^{commit}'], capture_output=True).returncode:
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', revision], check=True)
roots = ['ios', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
assert not subprocess.check_output(['git', 'diff', '--name-only', application, '--', *roots], text=True).strip(), 'Freeze the actual application, test cases and dependencies before UI'
for folder in ['ios/HarborTests', 'ios/HarborUITests', 'ios/HarborIntegrationTests']:
    changed = subprocess.check_output(['git', 'diff', '--name-only', native_source, application, '--', folder], text=True).splitlines()
    assert set(changed).issubset({'ios/HarborTests/TVDBProxyTests.swift', 'ios/HarborIntegrationTests/TVDBProxyLiveTests.swift'})
pin_path = 'ios/Harbor/Views/ProfilePINEntryView.swift'
old_pin = subprocess.check_output(['git', 'show', native_source + ':' + pin_path], text=True)
assert Path(pin_path).read_text('utf-8') == old_pin.replace('            .accessibilityIdentifier("profile-pin-screen")\n', '')
executions = execution_plan()
for row in executions:
    source = (Path('ios') / row['target'] / (row['suite'] + '.swift')).read_text('utf-8')
    assert re.search(r'\bfunc ' + re.escape(row['method']) + r'\(', source)
ui_cases = {row['target'] + '.' + row['suite'] + '/' + row['method'] for row in executions if not row['fixture']}
assert len(ui_cases) == 9
models = set()
for suite, count in [('ProfileLaunchTests', 8), ('AnimeEpisodeGroupingTests', 3)]:
    source = (Path('ios/HarborTests') / (suite + '.swift')).read_text('utf-8')
    methods = [name for name in re.findall(r'\bfunc (test\w+)\(', source) if not name.startswith('testPrepare')]
    assert len(methods) == count
    models.update('HarborTests.' + suite + '/' + name for name in methods)
preserved_language = 'HarborUITests.LanguageReferenceNavigationTests/testReferenceLanguagesSwitchInTheOrdinaryIPhoneSettings'
assert not ui_cases.intersection(models | {preserved_language})
prior = []
if not a.source_only:
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-focused-UI-preservation'}
    api = 'https://api.github.com/repos/' + os.environ.get('GITHUB_REPOSITORY', 'Said129/harbor')
    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, fp, code, message, response_headers, newurl): return None
    for number, source, conclusion in [(39172205813, old_source, 'failure'), (39229215940, native_source, 'success'), (39233004336, previous_ui, 'failure')]:
        metadata = get(f'/actions/runs/{number}')
        assert metadata['head_sha'] == source and metadata['status'] == 'completed' and metadata['conclusion'] == conclusion, 'Collect or repair the actual prerequisite before this UI dispatch'
        job = next(row for row in get(f'/actions/runs/{number}/jobs?per_page=100')['jobs'] if row['name'] == 'Apple SDK / Swift / iPhone')
        try: response = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers), timeout=45)
        except urllib.error.HTTPError as redirect:
            if redirect.code != 302: raise
            location = redirect.headers['Location']; assert urllib.parse.urlparse(location).scheme == 'https'
            response = urllib.request.urlopen(location, timeout=45)
        with response: data = response.read(32 * 1024 * 1024 + 1)
        assert len(data) <= 32 * 1024 * 1024
        text = data.decode('utf-8', errors='replace')
        outcomes = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", text)
        actual = {suite + '/' + method: result for suite, method, result in outcomes}
        assert len(actual) == len(outcomes), 'Require one real outcome per selected prerequisite method'
        if number == 39229215940:
            assert len(actual) == 11 and actual == {case: 'passed' for case in models}
            assert next(step for step in job['steps'] if step['name'] == 'Authenticate the eleven actual startup and anime model results')['conclusion'] == 'success'
        elif number == 39172205813:
            assert len(actual) == 27 and sum(result == 'passed' for result in actual.values()) == 26
            assert actual[preserved_language] == 'passed'
            assert actual['HarborUITests.HouseholdProfilesNavigationTests/testNormalProfileCreationIdentityAndRestartPINWorkOnIPhone'] == 'failed'
            assert sum(case.startswith('HarborTests.') and result == 'passed' for case, result in actual.items()) == 25
            assert 'Neither element nor any descendant has keyboard focus' in text
        else:
            failed_case = 'HarborUITests.HouseholdProfilesNavigationTests/testNormalProfileCreationIdentityAndRestartPINWorkOnIPhone'
            assert actual == {failed_case: 'failed'}, 'Preserve any new successful predecessors instead of repeating them'
            assert 'HouseholdProfilesNavigationTests.swift:81: error:' in text and 'profile-pin-entry' in text
            assert 'Neither element nor any descendant has keyboard focus' not in text
            assert next(step for step in job['steps'] if step['name'] == 'Preserve original startup and anime UI results')['conclusion'] == 'success'
        prior.append(dict(run=number, source=source, actual_outcomes=actual, raw_job_log_sha256=hashlib.sha256(data).hexdigest()))
proof = dict(source=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    application_source=application, approved_native_source=native_source, pin_identifier_repair_only=True,
    scope='startup-anime-ui', source_only=a.source_only, prior_runs_checked=not a.source_only,
    actual_prior_logs=prior, preserved_new_model_methods=sorted(models), preserved_phone_language=preserved_language,
    executions=executions, expected_actual_ui_cases=sorted(ui_cases), expected_ui_executions=9, required_setup_executions=4,
    expected_original_capture_count=40, prior_approved_methods_repeated=False, child_features_excluded=True,
    physical_device_validation=False, full_profile_parity=False, full_desktop_parity_complete=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Frozen source and thirteen selected executions inspected. ' + ('Actual prerequisite verification is pending; source-only inspection does not authorize dispatch.' if a.source_only else 'Actual prerequisite logs authenticated; approved model methods and iPhone language are retained.'))

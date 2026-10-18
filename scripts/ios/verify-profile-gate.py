"""Compile the integrated normal picker and execute only its two new editing gates."""
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
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
application = 'ab4a544fd9a64625cf5478ed54714039c10348fd'
editor_application = 'b0649c025dc92cc92370c548953a68b78d3bfed9'
for revision in [application, editor_application]:
    if subprocess.run(['git', 'cat-file', '-e', revision + '^{commit}'], capture_output=True).returncode:
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', revision], check=True)
def show(revision, path): return subprocess.check_output(['git', 'show', revision + ':' + path]).decode('utf-8')
roots = ['ios/Harbor', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
assert not subprocess.check_output(['git', 'diff', '--name-only', application, 'HEAD', '--', *roots], text=True).strip(), 'Freeze the entire reviewed application and its tests'
store = 'ios/Harbor/Services/HouseholdProfileStore.swift'
current = show(application, store)
start = current.index('    func requiresPIN(_ id: String) -> Bool {')
end = current.index('    var needsUpload: Bool', start)
assert current[:start] + current[end:] == show(editor_application, store), 'Only the new gate/query may change existing profile producers'
for path in ['ios/Harbor/Services/AppProfileContext.swift', 'ios/Harbor/Services/HouseholdSessionVault.swift', 'ios/Harbor/Services/ProfileSettingsStore.swift',
    'ios/Harbor/Services/ProfilePlaybackRegistry.swift', 'ios/Harbor/Services/HarborHouseholdSync.swift', 'ios/Harbor/Models/NativeProfileRoster.swift',
    'ios/Harbor/Models/HouseholdProfileDraft.swift', 'ios/Harbor/Services/DeviceProfileCredential.swift']:
    assert show(application, path) == show(editor_application, path), path
suites = ['HouseholdProfileTests', 'HouseholdSessionTests', 'AppProfileContextTests', 'ProfileLibraryBindingTests', 'ProfilePlaybackRegistryTests', 'ProfileSettingsTests', 'HouseholdRosterSyncTests']
first = set()
for suite in suites:
    path = f'ios/HarborTests/{suite}.swift'; source = show(editor_application, path)
    assert show(application, path) == source
    first.update('HarborTests.' + suite + '/' + name for name in re.findall(r'\bfunc (test\w+)\(', source))
assert len(first) == 55
first.add('HarborTests.PlaybackControlTests/testPausedResumeAndBackwardJumpReachTheRequestedPosition')
skipped = 'HarborTests.PlaybackControlTests/testPictureInPictureStartsFromPausedVideoAndRestoresTheSameSession'
editor_path = 'ios/HarborTests/ProfileEditorTransactionTests.swift'
editor = {'HarborTests.ProfileEditorTransactionTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, editor_path))}
assert show(application, editor_path) == show(editor_application, editor_path) and len(editor) == 6
repeated = {'HarborTests.HouseholdProfileTests/testRoutingMatchesLinkedSettingsAndOptionalPrivateContinueWatching',
    'HarborTests.HouseholdProfileTests/testReadAndWriteErrorsKeepTheCommittedRosterAndDisableFallbackOverwrite'}
pending = {'HarborTests.ProfileEditingGateTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, 'ios/HarborTests/ProfileEditingGateTests.swift'))}
assert len(pending) == 2
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-normal-picker-gates'}
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
def get(path):
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, response_headers, new_url): return None
logs = []
for number, source, expected in [
    (39119398009, '7cc9afe1dfdf88e14f6a04f332446375bb49e6a5', dict({case: 'passed' for case in first}, **{skipped: 'skipped'})),
    (39145711513, '5968b453dcd6f79b5396e459d75ed377229c033a', {case: 'passed' for case in editor | repeated})]:
    run = get(f'/actions/runs/{number}'); assert run['head_sha'] == source and run['status'] == 'completed' and run['conclusion'] == 'success'
    job = next(row for row in get(f'/actions/runs/{number}/jobs?per_page=100')['jobs'] if row['name'] == 'Apple SDK / Swift / iPhone')
    try: response = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers), timeout=45)
    except urllib.error.HTTPError as redirect:
        if redirect.code != 302: raise
        location = redirect.headers['Location']; assert urllib.parse.urlparse(location).scheme == 'https'
        response = urllib.request.urlopen(location, timeout=45)
    with response: data = response.read(32 * 1024 * 1024 + 1)
    assert len(data) <= 32 * 1024 * 1024
    rows = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", data.decode('utf-8', errors='replace'))
    assert len(rows) == len(expected) and {suite + '/' + name: result for suite, name, result in rows} == expected
    logs.append(dict(run=number, source=source, sha256=hashlib.sha256(data).hexdigest()))
proof = dict(source=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), scope='profile-gate',
    application_source=application, actual_prior_passes=62, prior_evidence_verified=True, prior_logs=logs,
    preserved_cases=sorted(first | editor), preserved_cases_count=62, prior_skipped_required=[skipped],
    pending_native_cases=sorted(pending), expected_actual_executions=2, new_native_cases=2,
    child_features_excluded=True, picker_sdk_compilation='pending', picker_ui_verification='pending',
    full_profile_parity=False, full_desktop_parity_complete=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('62 actual passes retained. Only two new editing-gate cases; integrated picker compilation and UI remain distinct evidence. No IPA.')

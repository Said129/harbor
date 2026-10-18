"""Preserve actual passes and execute only pending or affected profile checks/UI."""
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
application = '4ff6de8e85283bd2145ef4c204bfb03f675f8f61'
appearance = 'b0251a2f39abb93e3ed7a8a96e75e33ca8475932'
native_source = '4be6de4249331f04f9960137672b80e9526dc724'
gate_source = '7294a055f693619267228dfde094a1035c31d44d'
first_source = '7cc9afe1dfdf88e14f6a04f332446375bb49e6a5'
editor_source = '5968b453dcd6f79b5396e459d75ed377229c033a'
for revision in [application, appearance, native_source, gate_source, first_source, editor_source]:
    if subprocess.run(['git', 'cat-file', '-e', revision + '^{commit}'], capture_output=True).returncode:
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', revision], check=True)

def show(revision, path): return subprocess.check_output(['git', 'show', revision + ':' + path]).decode('utf-8')
roots = ['ios/Harbor', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
assert not subprocess.check_output(['git', 'diff', '--name-only', application, 'HEAD', '--', *roots], text=True).strip(), 'Freeze the reviewed picker application and UI tests'
assert set(subprocess.check_output(['git', 'diff', '--name-only', appearance, application, '--', *roots], text=True).splitlines()) == {
    'ios/Harbor/HarborApp.swift', 'ios/Harbor/ViewModels/AppModel.swift',
    'ios/Harbor/Services/ProfilePreferences.swift', 'ios/Harbor/Services/HouseholdAppearanceBinding.swift',
    'ios/Harbor/Views/HouseholdProfilesView.swift', 'ios/HarborTests/ProfileAppearanceTests.swift', 'ios/HarborTests/ProfileEditingGateTests.swift',
    'ios/HarborUITests/HouseholdProfilesNavigationTests.swift', 'ios/HarborUITests/LanguageReferenceNavigationTests.swift'}
model = 'ios/Harbor/ViewModels/AppModel.swift'
expected = show(appearance, model).replace('    var accountBusy = false\n', '    var accountBusy = false\n    private(set) var switchingProfile = false\n')
expected = expected.replace('profilesAfterAccount || profileContext.requiresSelection }', 'profilesAfterAccount || profileContext.requiresSelection || switchingProfile }')
expected = expected.replace('        accountBusy = true; showAccount = false; error = nil\n', '        accountBusy = true; switchingProfile = true; showAccount = false; error = nil\n')
start = expected.index('    @discardableResult func selectProfile(')
prefix, rest = expected[:start], expected[start:]
expected = prefix + rest.replace('        defer { accountBusy = false }', '        defer { accountBusy = false; switchingProfile = false }', 1)
assert expected == show(application, model), 'Only the activation-lifetime flag may change model behavior'
new_tests = {'HarborUITests.HouseholdProfilesNavigationTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, 'ios/HarborUITests/HouseholdProfilesNavigationTests.swift'))}
affected_ui = {'HarborUITests.LanguageReferenceNavigationTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, 'ios/HarborUITests/LanguageReferenceNavigationTests.swift'))}
assert len(new_tests) == len(affected_ui) == 2
appearance_path = 'ios/HarborTests/ProfileAppearanceTests.swift'
recovery_method = 'testUnreadableLegacyAppearanceCanRecoverOnExplicitRetryAndIsIgnoredAfterMigration'
appearance_tests = show(application, appearance_path)
start = appearance_tests.index('    func ' + recovery_method + '(')
end = appearance_tests.index('    func testInitializedProfilesIgnoreAnUnreadableLegacyCopy', start)
assert appearance_tests[:start] + appearance_tests[end:] == show(appearance, appearance_path), 'The eleven previously executed cases stay byte-identical'
appearance_cases = {'HarborTests.ProfileAppearanceTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(appearance, appearance_path))}
recovery_case = 'HarborTests.ProfileAppearanceTests/' + recovery_method
binding = 'ios/Harbor/Services/HouseholdAppearanceBinding.swift'
assert show(application, binding).replace('    var needsLegacyAppearance: Bool { profile?.appearanceInitialized != true }\n', '') == show(appearance, binding)
preferences = 'ios/Harbor/Services/ProfilePreferences.swift'
current = show(application, preferences).replace('        if household?.ready == true { legacyError = nil }\n', '')
prologue = '''        if let binding {
            if binding.needsLegacyAppearance && !legacyReady { reloadLegacy() }
            binding.reload(legacy: legacyValue, legacyReady: legacyReady)
            if binding.ready { legacyError = nil }; return
        }
        reloadLegacy()
    }
    private func reloadLegacy() {
'''
assert prologue in current
assert current.replace(prologue, '        if let binding { binding.reload(legacy: legacyValue, legacyReady: legacyReady); if binding.ready { legacyError = nil }; return }\n') == show(appearance, preferences)
editor = {'HarborTests.ProfileEditorTransactionTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, 'ios/HarborTests/ProfileEditorTransactionTests.swift'))}
assert show(application, 'ios/HarborTests/ProfileEditorTransactionTests.swift') == show(editor_source, 'ios/HarborTests/ProfileEditorTransactionTests.swift')
affected = editor | {'HarborTests.HouseholdProfileTests/' + name for name in [
    'testServerAdoptionPreservesDevicePINParentPINSharingAndMigrationOwner', 'testMissingRowsAreKeptButExplicitTombstonesRetireProfilesWithoutResurrection',
    'testRepeatedPullHasStableTimestampsNoEchoAndRejectsConflictingRevisions', 'testFirstPullNeverDeletesAnExistingGuestBasedOnItsName',
    'testRemoteAdoptionInvalidatesAnInFlightUnlockAndKeepsTheDeviceCredential']}
affected.add('HarborTests.HouseholdRosterSyncTests/testPullAdoptsTheFullRosterWithoutEchoAndKeepsDeviceCredentials')
gates = {'HarborTests.ProfileEditingGateTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, 'ios/HarborTests/ProfileEditingGateTests.swift'))}
assert len(appearance_cases | affected) == 23 and len(gates) == 2
corrected_gate = 'HarborTests.ProfileEditingGateTests/testRealPINAllowsEditingWithoutChangingTheSelectedAccountAndWrongPINNeverUnlocks'
passed_gate = 'HarborTests.ProfileEditingGateTests/testReloadDuringPINVerificationCannotGrantAnEditingUnlock'
gate_path = 'ios/HarborTests/ProfileEditingGateTests.swift'
old_fixture = '        var draft = HouseholdProfileDraft(profile: secondary); draft.name = "Protected edited"'
new_fixture = '        let editable = try XCTUnwrap(profiles.profiles.first { $0.id == secondary.id })\n        var draft = HouseholdProfileDraft(profile: editable); draft.name = "Protected edited"'
assert show(gate_source, gate_path).replace(old_fixture, new_fixture) == show(application, gate_path), 'Only fix the stale test fixture; retain the actual passed gate byte-for-byte'
view = 'ios/Harbor/Views/HouseholdProfilesView.swift'
old_catch = '        catch { error = safeMessage(error) }\n'
assert show(appearance, view).count(old_catch) == 1
assert show(appearance, view).replace(old_catch, '        catch { self.error = safeMessage(error) }\n') == show(application, view)
first = set()
for suite in ['HouseholdProfileTests', 'HouseholdSessionTests', 'AppProfileContextTests', 'ProfileLibraryBindingTests', 'ProfilePlaybackRegistryTests', 'ProfileSettingsTests', 'HouseholdRosterSyncTests']:
    path = f'ios/HarborTests/{suite}.swift'
    assert show(application, path) == show(first_source, path)
    first.update('HarborTests.' + suite + '/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(first_source, path)))
assert len(first) == 55
first.add('HarborTests.PlaybackControlTests/testPausedResumeAndBackwardJumpReachTheRequestedPosition')
skipped = 'HarborTests.PlaybackControlTests/testPictureInPictureStartsFromPausedVideoAndRestoresTheSameSession'
repeated = {'HarborTests.HouseholdProfileTests/testRoutingMatchesLinkedSettingsAndOptionalPrivateContinueWatching',
    'HarborTests.HouseholdProfileTests/testReadAndWriteErrorsKeepTheCommittedRosterAndDisableFallbackOverwrite'}
pending_native = appearance_cases | affected | {recovery_case, corrected_gate}
assert len(pending_native) == 25 and passed_gate not in pending_native
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-normal-profile-interface'}
assert os.environ.get('GITHUB_SHA', subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()) == subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), 'Review the same commit which will be dispatched'
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
def get(path):
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, response_headers, new_url): return None
prior = []
for number, source, conclusion, expected in [
    (39119398009, first_source, 'success', dict({case: 'passed' for case in first}, **{skipped: 'skipped'})),
    (39145711513, editor_source, 'success', {case: 'passed' for case in editor | repeated}),
    (39168437248, gate_source, 'failure', {corrected_gate: 'failed', passed_gate: 'passed'}),
    (39170580752, native_source, 'failure', {})]:
    run = get(f'/actions/runs/{number}')
    assert run['head_sha'] == source and run['status'] == 'completed' and run['conclusion'] == conclusion
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
    text = data.decode('utf-8', errors='replace')
    if number == 39168437248:
        assert 'caught error: "HarborError(code: "profile-editor-changed")"' in text, 'Require the reviewed stale fixture failure'
    if number == 39170580752:
        steps = {row['name']: row['conclusion'] for row in job['steps']}
        assert steps['Build simulator'] == 'failure' and steps['Run bridge and model tests on iPhone simulator'] == 'skipped'
        assert text.count('errorSummaries: file:///Users/runner/work/harbor/harbor/ios/Harbor/Views/HouseholdProfilesView.swift') == 2
        assert "Cannot assign to value: 'error' is immutable" in text and "Cannot assign value of type 'String' to type 'any Error'" in text
    prior.append(dict(run=number, source=source, actual_outcomes=expected, sha256=hashlib.sha256(data).hexdigest()))
proof = dict(source=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), application_source=application,
    scope='profile-ui', actual_prior_logs=prior, pending_new_ui_cases=sorted(new_tests), affected_previous_ui_cases=sorted(affected_ui),
    actual_prior_passes=63, preserved_cases=sorted((first | editor | {passed_gate}) - affected), preserved_case_count=51,
    expected_actual_cases=sorted(new_tests | affected_ui | pending_native), expected_actual_executions=29,
    pending_native_cases=sorted(pending_native), affected_native_cases=sorted(affected), corrected_gate_case=corrected_gate,
    previous_appearance_actual_executions=0, prior_native_tests_repeated=False,
    prior_skipped_required=['HarborTests.PlaybackControlTests/testPictureInPictureStartsFromPausedVideoAndRestoresTheSameSession'],
    photos_picker_ui_verification='pending', child_features_excluded=True, full_profile_parity=False, full_desktop_parity_complete=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Preserved 51 unchanged actual passes. Select 25 pending/affected native checks and four new/affected UI routes; no IPA.')

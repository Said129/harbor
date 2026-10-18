"""Freeze appearance integration; repeat only affected approved profile producers."""
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
application = 'b0251a2f39abb93e3ed7a8a96e75e33ca8475932'
picker = 'ab4a544fd9a64625cf5478ed54714039c10348fd'
first_source = '7cc9afe1dfdf88e14f6a04f332446375bb49e6a5'
editor_source = '5968b453dcd6f79b5396e459d75ed377229c033a'
for revision in [application, picker, first_source, editor_source]:
    if subprocess.run(['git', 'cat-file', '-e', revision + '^{commit}'], capture_output=True).returncode:
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', revision], check=True)

def show(revision, path): return subprocess.check_output(['git', 'show', revision + ':' + path]).decode('utf-8')
roots = ['ios/Harbor', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
assert not subprocess.check_output(['git', 'diff', '--name-only', application, 'HEAD', '--', *roots], text=True).strip(), 'Require the reviewed appearance application and tests'
allowed = {'ios/Harbor/' + path for path in ['Models/HouseholdProfileDraft.swift', 'Models/NativeProfileRoster.swift',
    'Services/HouseholdAppearanceBinding.swift', 'Services/HouseholdProfileStore.swift', 'Services/ProfilePhotoStore.swift',
    'Services/ProfilePreferences.swift', 'ViewModels/AppModel.swift', 'Views/HarborShell.swift', 'Views/HouseholdProfilesView.swift']}
allowed.add('ios/HarborTests/ProfileAppearanceTests.swift')
assert set(subprocess.check_output(['git', 'diff', '--name-only', picker, application, '--', *roots], text=True).splitlines()) == allowed
model = 'ios/Harbor/Models/NativeProfileRoster.swift'
assert show(application, model).replace('    var localPhotoID: String? = nil\n    var appearanceInitialized: Bool? = nil\n', '') == show(picker, model)
store = 'ios/Harbor/Services/HouseholdProfileStore.swift'
def between(source, start, end): return source[source.index(start):source.index(end, source.index(start))]
for start, end in [('    func requiresPIN(', '    var needsUpload:'), ('    func shareStremio(', '    /// A missing server row'),
                   ('    func bindSynchronization(', '\n}')]:
    assert between(show(application, store), start, end) == between(show(picker, store), start, end), start
suites = ['HouseholdProfileTests', 'HouseholdSessionTests', 'AppProfileContextTests', 'ProfileLibraryBindingTests',
          'ProfilePlaybackRegistryTests', 'ProfileSettingsTests', 'HouseholdRosterSyncTests']
first = set()
for suite in suites:
    path = f'ios/HarborTests/{suite}.swift'; source = show(first_source, path)
    assert show(application, path) == source
    first.update('HarborTests.' + suite + '/' + name for name in re.findall(r'\bfunc (test\w+)\(', source))
assert len(first) == 55
first.add('HarborTests.PlaybackControlTests/testPausedResumeAndBackwardJumpReachTheRequestedPosition')
skipped = 'HarborTests.PlaybackControlTests/testPictureInPictureStartsFromPausedVideoAndRestoresTheSameSession'
editor_path = 'ios/HarborTests/ProfileEditorTransactionTests.swift'
assert show(application, editor_path) == show(editor_source, editor_path)
editor = {'HarborTests.ProfileEditorTransactionTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, editor_path))}
assert len(editor) == 6
repeated = {'HarborTests.HouseholdProfileTests/testRoutingMatchesLinkedSettingsAndOptionalPrivateContinueWatching',
            'HarborTests.HouseholdProfileTests/testReadAndWriteErrorsKeepTheCommittedRosterAndDisableFallbackOverwrite'}
affected = editor | {'HarborTests.HouseholdProfileTests/' + name for name in [
    'testServerAdoptionPreservesDevicePINParentPINSharingAndMigrationOwner',
    'testMissingRowsAreKeptButExplicitTombstonesRetireProfilesWithoutResurrection',
    'testRepeatedPullHasStableTimestampsNoEchoAndRejectsConflictingRevisions',
    'testFirstPullNeverDeletesAnExistingGuestBasedOnItsName',
    'testRemoteAdoptionInvalidatesAnInFlightUnlockAndKeepsTheDeviceCredential']}
affected.add('HarborTests.HouseholdRosterSyncTests/testPullAdoptsTheFullRosterWithoutEchoAndKeepsDeviceCredentials')
assert len(affected) == 12 and affected <= first | editor
prepared = {'HarborTests.ProfileAppearanceTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, 'ios/HarborTests/ProfileAppearanceTests.swift'))}
assert len(prepared) == 11
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-profile-appearance-review'}
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
def get(path):
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, response_headers, new_url): return None
logs = []
for number, source, expected in [
    (39119398009, first_source, dict({case: 'passed' for case in first}, **{skipped: 'skipped'})),
    (39145711513, editor_source, {case: 'passed' for case in editor | repeated})]:
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
proof = dict(source=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), scope='profile-appearance',
    application_source=application, actual_prior_passes=62, prior_evidence_verified=True, prior_logs=logs,
    preserved_cases=sorted((first | editor) - affected), preserved_cases_count=50, prior_skipped_required=[skipped],
    prepared_new_cases=sorted(prepared), affected_previous_cases=sorted(affected),
    expected_actual_cases=sorted(prepared | affected), expected_actual_executions=23,
    separate_gate_validation_run=39168437248, separate_gate_results_claimed=False,
    child_features_excluded=True, picker_ui_verification='pending', full_profile_parity=False, full_desktop_parity_complete=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
a.output.with_name('profile-appearance-selection.txt').write_text(''.join(case.replace('HarborTests.', 'HarborTests/') + '\n' for case in sorted(prepared | affected)), 'utf-8')
print('Preserved 50 unchanged actual passes; selected 11 new appearance checks and 12 affected approved cases. No UI or IPA claim.')

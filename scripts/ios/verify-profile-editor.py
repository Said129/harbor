"""Freeze editor changes and preserve the actual approved profile model results."""
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
application = 'b0649c025dc92cc92370c548953a68b78d3bfed9'
prior_application = '49110c6786903d6480c2febe101d8210f2a4fb9b'
prior_source = '7cc9afe1dfdf88e14f6a04f332446375bb49e6a5'
prior_run = 39119398009
for revision in [application, prior_application]:
    if subprocess.run(['git', 'cat-file', '-e', revision + '^{commit}'], capture_output=True).returncode != 0:
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', revision], check=True)
def show(revision, path): return subprocess.check_output(['git', 'show', revision + ':' + path]).decode('utf-8')
roots = ['ios/Harbor', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
assert not subprocess.check_output(['git', 'diff', '--name-only', application, 'HEAD', '--', *roots], text=True).strip(), 'Require the frozen editor application and tests'
allowed = {'ios/Harbor/Models/HouseholdProfileDraft.swift', 'ios/Harbor/Services/DeviceProfileCredential.swift',
    'ios/Harbor/Services/HouseholdProfileStore.swift', 'ios/Harbor/Views/ProfilePINEntryView.swift'}
assert set(subprocess.check_output(['git', 'diff', '--name-only', prior_application, application, '--', 'ios/Harbor'], text=True).splitlines()) == allowed
old = show(prior_application, 'ios/Harbor/Services/HouseholdProfileStore.swift')
new = show(application, 'ios/Harbor/Services/HouseholdProfileStore.swift')
start = old.index('    @discardableResult func create('); end = old.index('    func edit(', start)
old_create = old[start:end]
creation = old_create.split('        try requireEdit()\n', 1)[1]
split = creation.index('        var next = state; next.profiles.append(profile)')
value = creation[:split].replace('        let profile = DeviceHouseholdProfile', '        return DeviceHouseholdProfile')
helper = '    private func newProfile(name: String, avatar: String?, color: String, kid: JSONValue, legacyOwner: String? = nil) throws -> DeviceHouseholdProfile {\n' + value + '    }\n'
wrapper = old_create[:old_create.index('        try requireEdit()\n')] + '        try requireEdit()\n' + '        let profile = try newProfile(name: name, avatar: avatar, color: color, kid: kid, legacyOwner: legacyOwner)\n' + creation[split:]
assert wrapper + helper in new, 'Existing creation must retain its exact values and atomic commit after extraction'
assert new[new.index('    func edit('):] == old[end:], 'Previously approved edit, selection, lock, adoption and roster sync implementations must stay unchanged'
deriver = '''protocol ProfileCredentialDeriving: Sendable {
    func derive(_ password: String) async throws -> DeviceProfileCredential
}
struct DeviceProfileCredentialDeriver: ProfileCredentialDeriving {
    func derive(_ password: String) async throws -> DeviceProfileCredential { try await DeviceProfileCredential.create(password) }
}
'''
assert show(application, 'ios/Harbor/Services/DeviceProfileCredential.swift').replace(deriver, '') == show(prior_application, 'ios/Harbor/Services/DeviceProfileCredential.swift')
suites = ['HouseholdProfileTests', 'HouseholdSessionTests', 'AppProfileContextTests', 'ProfileLibraryBindingTests', 'ProfilePlaybackRegistryTests', 'ProfileSettingsTests', 'HouseholdRosterSyncTests']
prior = set()
for suite in suites:
    path = f'ios/HarborTests/{suite}.swift'
    text = show(prior_application, path); assert show(application, path) == text
    prior.update('HarborTests.' + suite + '/' + name for name in re.findall(r'\bfunc (test\w+)\(', text))
assert len(prior) == 55
prior.add('HarborTests.PlaybackControlTests/testPausedResumeAndBackwardJumpReachTheRequestedPosition')
skipped = 'HarborTests.PlaybackControlTests/testPictureInPictureStartsFromPausedVideoAndRestoresTheSameSession'
affected = {'HarborTests.HouseholdProfileTests/testRoutingMatchesLinkedSettingsAndOptionalPrivateContinueWatching',
    'HarborTests.HouseholdProfileTests/testReadAndWriteErrorsKeepTheCommittedRosterAndDisableFallbackOverwrite'}
assert affected <= prior
prepared = {'HarborTests.ProfileEditorTransactionTests/' + name for name in re.findall(r'\bfunc (test\w+)\(', show(application, 'ios/HarborTests/ProfileEditorTransactionTests.swift'))}
assert len(prepared) == 6
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-profile-editor-review'}
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
def get(path):
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
run = get(f'/actions/runs/{prior_run}'); assert run['head_sha'] == prior_source and run['status'] == 'completed' and run['conclusion'] == 'success'
job = next(row for row in get(f'/actions/runs/{prior_run}/jobs?per_page=100')['jobs'] if row['name'] == 'Apple SDK / Swift / iPhone')
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
rows = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", data.decode('utf-8', errors='replace'))
outcomes = {suite + '/' + name: result for suite, name, result in rows}
assert len(rows) == len(outcomes) == 57 and outcomes == dict({case: 'passed' for case in prior}, **{skipped: 'skipped'})
proof = dict(source=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    scope='profile-editor', application_source=application, prior_application=prior_application, prior_source=prior_source, prior_run=prior_run,
    actual_prior_passes=56, prior_skipped_required=[skipped], prior_job_log_sha256=hashlib.sha256(data).hexdigest(),
    preserved_cases=sorted(prior - affected), affected_previous_cases=sorted(affected), prepared_new_cases=sorted(prepared),
    expected_actual_cases=sorted(prepared | affected), expected_actual_executions=8,
    existing_creation_values_and_commit_preserved=True, existing_lock_and_sync_implementations_byte_identical=True,
    new_editor_execution_results='pending', selector_exposed=False, profile_pin_visual_review='pending',
    full_desktop_parity_complete=False, physical_device_validation=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('56 actual prior passes reviewed; preserve 54, execute six new editor cases and two affected creation cases. PiP remains unverified; no IPA.')

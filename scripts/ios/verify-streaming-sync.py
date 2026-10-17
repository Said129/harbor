"""Preserve the accepted service browser while reviewing scoped service sync."""
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
p.add_argument('--source-review-only', action='store_true', help='Review a source slice without claiming prior Apple execution')
a = p.parse_args()
assert not (a.working_tree and os.environ.get('GITHUB_ACTIONS'))
previous = os.environ.get('HARBOR_PREVIOUS_SOURCE') or '9a68eb118f6304301d7a96560f2b9409897d0f87'
current = os.environ.get('HARBOR_CURRENT_SOURCE', 'HEAD')
assert current == 'HEAD' or re.fullmatch('[a-f0-9]{40}', current)
assert not a.working_tree or current == 'HEAD'
assert re.fullmatch('[a-f0-9]{40}', previous)
if subprocess.run(['git', 'cat-file', '-e', previous + '^{commit}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
    subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', previous], check=True)
if current != 'HEAD' and subprocess.run(['git', 'cat-file', '-e', current + '^{commit}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
    subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', current], check=True)
def blob(ref, name):
    if a.working_tree and ref == 'HEAD': return Path(name).read_text('utf-8').replace('\r\n', '\n')
    if ref == 'HEAD': ref = current
    return subprocess.check_output(['git', 'show', ref + ':' + name]).decode('utf-8')
def changes(roots):
    command = ['git', 'diff', '--name-only', previous] + ([] if a.working_tree else [current]) + ['--', *roots]
    result = set(subprocess.check_output(command, text=True).splitlines())
    if a.working_tree: result.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *roots], text=True).splitlines())
    return result
codes = ['en', 'ar', 'zh', 'fr', 'de', 'hi', 'id', 'it', 'ja', 'ko', 'pl', 'pt', 'ru', 'es', 'tr', 'vi']
allowed = {'ios/Harbor/Services/StreamingPreferences.swift', 'ios/Harbor/Services/HarborStreamingSync.swift',
           'ios/Harbor/Services/HarborProfileSync.swift', 'ios/Harbor/ViewModels/AppModel.swift',
           'ios/Harbor/Views/StreamingSettingsView.swift', 'ios/Harbor/NativeInterfaceTranslations.json'}
allowed.update(f'ios/Harbor/{code}.lproj/Localizable.strings' for code in codes)
assert changes(['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']) == allowed
name = 'ios/Harbor/Services/StreamingPreferences.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
assert before.split('@MainActor protocol StreamingPreferencePersistence')[0] == after.split('@MainActor protocol StreamingPreferencePersistence')[0]
assert before[before.index('enum StreamingCatalog {'):] == after[after.index('enum StreamingCatalog {'):], 'Catalog producers and browser paging are unchanged'
name = 'ios/Harbor/ViewModels/AppModel.swift'
expected = blob(previous, name)
expected = expected.replace('        InterfacePreferences.shared.navigation.bind(.local(owner: owner))\n', '        InterfacePreferences.shared.navigation.bind(.local(owner: owner))\n        StreamingPreferences.forOwner(owner).bind(.local(owner: owner))\n', 1)
expected = expected.replace('        if previousOwner != session.user.id { InterfacePreferences.shared.navigation.bind(.local(owner: session.user.id)) }', '''        if previousOwner != session.user.id {
            StreamingPreferences.forOwner(previousOwner).suspend()
            InterfacePreferences.shared.navigation.bind(.local(owner: session.user.id))
            StreamingPreferences.forOwner(session.user.id).bind(.local(owner: session.user.id))
        }''', 1)
expected = expected.replace('        InterfacePreferences.shared.navigation.bind(.local(owner: "guest"))\n', '        InterfacePreferences.shared.navigation.bind(.local(owner: "guest"))\n        StreamingPreferences.forOwner("guest").bind(.local(owner: "guest"))\n', 1)
expected = expected.replace('        try keychain.remove("account.v1")\n', '        try keychain.remove("account.v1")\n        StreamingPreferences.forOwner(savedAccount?.session.user.id ?? "guest").suspend()\n', 1)
assert blob('HEAD', name) == expected, 'Preserve account, playback, continuity and addon behavior outside the service scope bindings and suspensions'
name = 'ios/Harbor/Services/HarborProfileSync.swift'
expected = blob(previous, name)
expected = expected.replace('    private weak var profile: ProfilePreferences?', '    @ObservationIgnored lazy var services = HarborStreamingSync(owner: owner, preferences: StreamingPreferences.forOwner(owner))\n    private weak var profile: ProfilePreferences?', 1)
expected = expected.replace('stored.pending != nil || navigation.hasPendingChanges }', 'stored.pending != nil || navigation.hasPendingChanges || services.hasPendingChanges }', 1)
expected = expected.replace('\n                navigation.unbind()\n', '\n                navigation.unbind()\n                services.unbind()\n                StreamingPreferences.forOwner(owner).bind(.local(owner: owner))\n', 1)
expected = expected.replace('\n            navigation.unbind()\n', '\n            navigation.unbind()\n            services.unbind()\n            StreamingPreferences.forOwner(owner).bind(.local(owner: owner))\n', 1)
expected = expected.replace('        try await navigation.synchronize(state: state, account: session.id, profile: final) { [weak self] body in', '        services.requestSync = { [weak self] in self?.scheduleSync() }\n        let send: @MainActor (JSONValue) async throws -> JSONValue = { [weak self] body in', 1)
expected = expected.replace('            return try await self.request("/sync/v1/push", method: "POST", body: body, scope: scope)\n        }\n', '            return try await self.request("/sync/v1/push", method: "POST", body: body, scope: scope)\n        }\n        try await navigation.synchronize(state: state, account: session.id, profile: final, send: send)\n        try await services.synchronize(state: state, account: session.id, profile: final, send: send)\n', 1)
assert blob('HEAD', name) == expected, 'Preserve the existing session format, auth refresh, roster and navigation transport'
name = 'ios/Harbor/Views/StreamingSettingsView.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
assert before[before.index('struct StreamingServiceLogo:'):] == after[after.index('struct StreamingServiceLogo:'):]
cloud_start = after.index('                let cloud = ProfilePreferences.forOwner(')
cloud_end = after.index('            }.padding(20)', cloud_start)
panel = after[cloud_start:cloud_end]
assert all(value in panel for value in ['cloud.services.restoreMyVersion()', 'await cloud.sync()', 'services-restore-version', 'services-sync-now', 'cloudWritePending'])
after = after[:cloud_start] + after[cloud_end:]
after = after.replace('                    let scope = preferences.scope\n', '', 1).replace('preferences.setEnabled(!enabled, for: service.key, in: scope)', 'preferences.setEnabled(!enabled, for: service.key)', 1)
after = after.replace('!preferences.ready || preferences.cloudWritePending', '!preferences.ready', 1)
assert before == after, 'Preserve service picker geometry and the accepted browser entry'
def strings(value): return {json.loads(key): json.loads(text) for key, text in re.findall(r'^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$', value, re.M)}
for code in codes:
    name = f'ios/Harbor/{code}.lproj/Localizable.strings'
    before, after = (strings(blob(ref, name)) for ref in [previous, 'HEAD'])
    assert all(after.get(key) == value for key, value in before.items()), code
name = 'ios/Harbor/NativeInterfaceTranslations.json'
before, after = (json.loads(blob(ref, name)) for ref in [previous, 'HEAD'])
assert all(all(after[code].get(key) == value for key, value in rows.items()) for code, rows in before.items())
messages = {'Could not restore your services. The saved version is kept.', 'Your services are saved locally. Cloud sync will retry.', 'Another device changed services. Your previous version is saved on this device.', 'Services changes waiting to sync'}
assert all(all(after[code].get(key) for key in messages) for code in codes)
tests = {'ios/HarborTests/StreamingSyncTests.swift', 'ios/HarborUITests/StreamingSelectionNavigationTests.swift'}
assert changes(['ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests']) == tests
assert len(re.findall(r'\bfunc test\w+\(', blob('HEAD', 'ios/HarborTests/StreamingSyncTests.swift'))) == 13
assert len(re.findall(r'\bfunc test\w+\(', blob('HEAD', 'ios/HarborUITests/StreamingSelectionNavigationTests.swift'))) == 2
proof = dict(source=os.environ.get('GITHUB_SHA'), previous_source=previous, scope='streaming-sync', local_source_review_only=a.working_tree,
             intermediate_source_review_only=a.source_review_only,
             prior_evidence_verified=False, new_native_methods=13, affected_existing_native_methods=2, new_ui_methods=2,
             expected_actual_executions=17, expected_new_images=4, ipa_created=False,
             physical_device_validation=False, complete_multi_profile_ui=False, full_desktop_parity_complete=False)
if not a.working_tree and not a.source_review_only:
    api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-streaming-sync-validation'}
    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
    ids = os.environ['HARBOR_PREVIOUS_RUNS'].split(','); assert all(re.fullmatch('[0-9]+', value) for value in ids)
    approved = [run for run in [get('/actions/runs/' + value) for value in ids] if run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] == 'success']
    assert len(approved) == 1, 'Require the actually completed service browser validation'
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
    outcomes = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", data.decode('utf-8', errors='replace'))
    assert len(outcomes) == 7 and len({row[:2] for row in outcomes}) == 7 and all(row[2] == 'passed' for row in outcomes)
    proof.update(prior_evidence_verified=True, preserved_service_run=run['id'], preserved_actual_cases=['/'.join(row[:2]) for row in outcomes], previous_job_log_sha256=hashlib.sha256(data).hexdigest())
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Streaming sync source scope reviewed; ' + ('Apple validation pending.' if a.working_tree or a.source_review_only else 'actual accepted service browser outcomes preserved.'))

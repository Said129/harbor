"""Validate navigation scope and preserve actual approved, unchanged behavior."""
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
p.add_argument('--working-tree', action='store_true', help='Local static review only; never accepted as CI evidence')
a = p.parse_args()
assert not (a.working_tree and os.environ.get('GITHUB_ACTIONS')), 'CI must verify committed source and prior results'
previous = 'eeb006f5747ace59a65e8191104eaaeed38e15b2'
if subprocess.run(['git', 'cat-file', '-e', previous + '^{commit}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
    subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', previous], check=True)
codes = ['en', 'ar', 'zh', 'fr', 'de', 'hi', 'id', 'it', 'ja', 'ko', 'pl', 'pt', 'ru', 'es', 'tr', 'vi']
allowed = {
    'ios/Harbor/HarborApp.swift', 'ios/Harbor/NativeInterfaceTranslations.json',
    'ios/Harbor/Services/HarborProfileSync.swift', 'ios/Harbor/Services/InterfacePreferences.swift',
    'ios/Harbor/Services/DesktopNavigationLayout.swift', 'ios/Harbor/Services/ScopedNavigationPreferences.swift',
    'ios/Harbor/Services/HarborNavigationSync.swift', 'ios/Harbor/ViewModels/AppModel.swift',
    'ios/Harbor/Views/InterfaceSettingsView.swift',
    'ios/Harbor/Services/ArtworkStore.swift',
}
allowed.update(f'ios/Harbor/{code}.lproj/Localizable.strings' for code in codes)
roots = ['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']
command = ['git', 'diff', '--name-only', previous] + ([] if a.working_tree else ['HEAD']) + ['--', *roots]
changed = set(subprocess.check_output(command, text=True).splitlines())
if a.working_tree: changed.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *roots], text=True).splitlines())
assert changed == allowed, 'Review any change beyond navigation models, wiring, UI and additive labels'

def blob(ref, name):
    if a.working_tree and ref == 'HEAD': return Path(name).read_text('utf-8').replace('\r\n', '\n')
    return subprocess.check_output(['git', 'show', ref + ':' + name]).decode('utf-8')

name = 'ios/Harbor/ViewModels/AppModel.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
expected = before.replace('    private func setProgressOwner(_ owner: String) async {\n', '    private func setProgressOwner(_ owner: String) async {\n        InterfacePreferences.shared.navigation.bind(.local(owner: owner))\n', 1)
expected = expected.replace('        let previousOwner = savedAccount?.session.user.id ?? "guest"\n', '        let previousOwner = savedAccount?.session.user.id ?? "guest"\n        if previousOwner != session.user.id { InterfacePreferences.shared.navigation.bind(.local(owner: session.user.id)) }\n', 1)
expected = expected.replace('        try keychain.remove("account.v1")\n', '        try keychain.remove("account.v1")\n        InterfacePreferences.shared.navigation.bind(.local(owner: "guest"))\n', 1)
assert after == expected, 'The account/addon/progress operations must remain intact'
name = 'ios/Harbor/HarborApp.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
assert after == before.replace('.task(id: (model.user?.id ?? "guest") + "|" + String(describing: scenePhase)) {\n                    guard scenePhase == .active else { return }', '.task(id: (model.user?.id ?? "guest") + "|" + String(model.storageReady) + "|" + String(describing: scenePhase)) {\n                    guard scenePhase == .active, model.storageReady else { return }', 1)
name = 'ios/Harbor/Services/ArtworkStore.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
assert after == before.replace('            guard CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw HarborError(code: "invalid-artwork") }', '            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) != nil,\n                  CGImageSourceGetCount(source) > 0, CGImageSourceGetStatus(source) == .statusComplete else {\n                session.configuration.urlCache?.removeCachedResponse(for: request)\n                throw HarborError(code: "invalid-artwork")\n            }', 1), 'Only strengthen shared image-container validation and evict invalid HTTP responses; rerun affected image cases'
name = 'ios/Harbor/Services/HarborProfileSync.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
assert before.split('@MainActor @Observable', 1)[0] == after.split('@MainActor @Observable', 1)[0], 'The roster parser and profile-field rules changed'
for kind in ['Session', 'Pending', 'Stored']:
    pattern = rf'^    private struct {kind}: Codable .*?$'
    assert re.search(pattern, before, re.M).group() == re.search(pattern, after, re.M).group(), 'The saved authentication/profile queue format changed'
def authenticated_method(text): return text.split('    private func request(', 1)[1].split('    private func synchronize(', 1)[0]
assert authenticated_method(before) == authenticated_method(after), 'Token refresh, redirect/request handling or generation checks changed'
name = 'ios/Harbor/Services/InterfacePreferences.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
def unchanged_preferences(text):
    return {name: line for line in text.splitlines() if (match := re.match(r'    var (\w+)', line)) and (name := match[1]) not in ['navigationOrder', 'navigationHidden', 'navigationNames', 'defaultNavigationOrder', 'orderedSections']}
assert unchanged_preferences(before) == unchanged_preferences(after), 'Unrelated motion, layout or spoiler preferences changed'
name = 'ios/Harbor/Views/InterfaceSettingsView.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
assert before.split('struct NavigationSettingsView:', 1)[0] == after.split('struct NavigationSettingsView:', 1)[0]
def home_picker(text): return text.split('private struct HomeStylePicker:', 1)[1].split('private struct NavigationSettingRow:', 1)[0]
assert home_picker(before) == home_picker(after), 'Home layout controls changed'
def strings(value): return {json.loads(key): json.loads(text) for key, text in re.findall(r'^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$', value, re.M)}
for code in codes:
    name = f'ios/Harbor/{code}.lproj/Localizable.strings'
    old, new = (strings(blob(ref, name)) for ref in [previous, 'HEAD'])
    assert old and all(new.get(key) == value for key, value in old.items()), f'Approved {code} labels changed'
name = 'ios/Harbor/NativeInterfaceTranslations.json'
before, after = (json.loads(blob(ref, name)) for ref in [previous, 'HEAD'])
assert all(all(after[code].get(key) == value for key, value in labels.items()) for code, labels in before.items())
tests = {'ios/HarborTests/NavigationScopeTests.swift', 'ios/HarborTests/NavigationSyncTests.swift', 'ios/HarborUITests/NavigationCustomizationTests.swift'}
test_roots = ['ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests']
test_command = ['git', 'diff', '--name-only', previous] + ([] if a.working_tree else ['HEAD']) + ['--', *test_roots]
changed_tests = set(subprocess.check_output(test_command, text=True).splitlines())
if a.working_tree: changed_tests.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *test_roots], text=True).splitlines())
assert changed_tests == tests
assert sum(len(re.findall(r'\bfunc test\w+\(', blob('HEAD', name))) for name in tests) == 20
proof = dict(source=os.environ.get('GITHUB_SHA'), previous_source=previous, scope='navigation-sync', local_source_review_only=a.working_tree,
             prior_evidence_verified=False, new_native_methods=18, new_ui_methods=2, affected_image_methods=3, pending_system_language_ui_methods=4,
             expected_actual_executions=27, expected_new_images=26, ipa_created=False,
             full_desktop_parity_complete=False, physical_two_device_sync_verified=False,
             unchanged_authenticated_method_sha256=hashlib.sha256(authenticated_method(blob('HEAD', 'ios/Harbor/Services/HarborProfileSync.swift')).encode()).hexdigest())
if not a.working_tree:
    api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-navigation-validation'}
    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
    run = get('/actions/runs/39045971697')
    assert run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] == 'failure'
    jobs = get('/actions/runs/39045971697/jobs?per_page=100')['jobs']
    primary = next(job for job in jobs if job['name'] == 'Apple SDK / Swift / iPhone')
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, file, code, message, response_headers, new_url): return None
    try: logs = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(api + f'/actions/jobs/{primary["id"]}/logs', headers=headers), timeout=45)
    except urllib.error.HTTPError as redirect:
        if redirect.code != 302: raise
        location = redirect.headers['Location']; parsed = urllib.parse.urlparse(location)
        assert parsed.scheme == 'https' and parsed.hostname
        logs = urllib.request.urlopen(location, timeout=45)
    with logs: data = logs.read(32 * 1024 * 1024 + 1)
    assert len(data) <= 32 * 1024 * 1024
    outcomes = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", data.decode('utf-8', errors='replace'))
    failed = ('HarborTests.ArtworkMaintenanceTests', 'testEveryCoalescedConsumerRejectsInvalidImageData', 'failed')
    assert len(outcomes) == 12 and [row for row in outcomes if row[2] != 'passed'] == [failed], 'Preserve actual successes only; invalid-image handling is revalidated'
    assert not any('StableMobileTests' in row[0] for row in outcomes)
    steps = {step['name']: step['conclusion'] for step in primary['steps']}
    assert steps['Build simulator'] == 'success' and steps['Run bridge and model tests on iPhone simulator'] == 'failure'
    assert steps['Run native UI on the selected simulator'] == steps['Run the affected system maintenance UI on iPad'] == 'skipped'
    assert all(steps[name] == 'skipped' for name in ['Build device without signing', 'Package and verify unsigned iPhone IPA', 'Save verified unsigned IPA in a draft Release'])
    preserved = ['/'.join(row[:2]) for row in outcomes if row[2] == 'passed' and row[0] != 'HarborTests.ArtworkMaintenanceTests']
    revalidated = ['/'.join(row[:2]) for row in outcomes if row[2] == 'passed' and row[0] == 'HarborTests.ArtworkMaintenanceTests']
    assert len(preserved) == 9 and len(revalidated) == 2
    proof.update(prior_evidence_verified=True, previous_run=39045971697, prior_run_conclusion='failure', preserved_actual_cases=preserved,
                 affected_previously_passed_cases_revalidated=revalidated, reason_for_image_revalidation='The new ImageIO count/type/status guard affects accepted image inputs as well as the failed invalid-data path.',
                 reviewed_failed_case='/'.join(failed[:2]), previous_job_log_sha256=hashlib.sha256(data).hexdigest(),
                 preserved_native_language_case_run=39028548982, preserved_native_vector_captures_run=39045971697)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Navigation source scope verified; ' + ('local review only, Apple results still pending.' if a.working_tree else 'actual prior approved cases preserved.'))

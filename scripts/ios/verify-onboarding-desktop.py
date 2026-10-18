"""Preserve unrelated approved behavior while validating the native ten-stage setup."""
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
p.add_argument('--output', required=True, type=Path)
p.add_argument('--working-tree', action='store_true')
a = p.parse_args()
assert not (a.working_tree and os.environ.get('GITHUB_ACTIONS')), 'CI verifies committed source only'
previous = os.environ.get('HARBOR_PREVIOUS_SOURCE', 'c70ba2dab84b6e8fd37b37abef097cfcc4933dd4')
assert re.fullmatch('[a-f0-9]{40}', previous)
if subprocess.run(['git', 'cat-file', '-e', previous + '^{commit}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
    subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', previous], check=True)

def blob(ref, name):
    if ref == 'HEAD' and a.working_tree: return Path(name).read_bytes()
    return subprocess.check_output(['git', 'show', ref + ':' + name])

def text(ref, name): return blob(ref, name).decode('utf-8').replace('\r\n', '\n')

def changed(roots):
    command = ['git', 'diff', '--name-only', previous] + ([] if a.working_tree else ['HEAD']) + ['--', *roots]
    result = set(subprocess.check_output(command, text=True).splitlines())
    if a.working_tree: result.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *roots], text=True).splitlines())
    return result

codes = ['en', 'ar', 'zh', 'fr', 'de', 'hi', 'id', 'it', 'ja', 'ko', 'pl', 'pt', 'ru', 'es', 'tr', 'vi']
allowed = {
    'ios/Harbor/DesktopLanguages.json', 'ios/Harbor/DesktopStreamingServices.json', 'ios/Harbor/DesktopStreamingSources.json',
    'ios/Harbor/DesktopOnboardingSources.json', 'ios/Harbor/NativeInterfaceTranslations.json',
    'ios/Harbor/Services/InterfaceLanguage.swift', 'ios/Harbor/Services/StreamingPreferences.swift',
    'ios/Harbor/Services/OnboardingContent.swift', 'ios/Harbor/Services/DiscoveryPreferences.swift',
    'ios/Harbor/ViewModels/HomeContentModel.swift', 'ios/Harbor/Views/HomeView.swift', 'ios/Harbor/Views/DiscoveryRails.swift',
    'ios/Harbor/Views/AppWalkthroughView.swift', 'ios/Harbor/Views/OnboardingSplash.swift', 'ios/Harbor/Views/OnboardingSteps.swift',
    'ios/Harbor/Views/StreamingSettingsView.swift', 'ios/Harbor/Views/HarborShell.swift',
    'ios/Harbor/Views/InterfaceSettingsView.swift', 'ios/Harbor/Views/SettingsView.swift',
    'ios/Harbor/Views/SystemStorageView.swift', 'ios/Harbor/Views/SystemAboutView.swift', 'ios/Harbor/Views/ProfileEditor.swift',
    'ios/Harbor/Assets.xcassets/home-style-classic.imageset/still.png', 'ios/Harbor/Assets.xcassets/home-style-harbor.imageset/still.png',
    'ios/Harbor/Assets.xcassets/onboarding-thumbsup.imageset/Contents.json', 'ios/Harbor/Assets.xcassets/onboarding-thumbsup.imageset/still.png',
}
services = json.loads(text('HEAD', 'ios/Harbor/DesktopStreamingServices.json'))
assert len(services) == 27 and sum(service['enabledByDefault'] for service in services) == 12
for service in services:
    assert re.fullmatch('streaming-[a-z]+', service['asset'])
    allowed.update('ios/Harbor/Assets.xcassets/' + service['asset'] + '.imageset/' + name for name in ['Contents.json', 'logo.png'])
allowed.update(f'ios/Harbor/{code}.lproj/Localizable.strings' for code in codes)
assert changed(['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']) == allowed, 'Review any production changes outside onboarding, service rows and additive language metadata'
assert sum(len(blob('HEAD', 'ios/Harbor/Assets.xcassets/' + service['asset'] + '.imageset/logo.png')) for service in services) < 512 * 1_024

name = 'ios/Harbor/Views/HarborShell.swift'
expected = text(previous, name).replace('{ AppWalkthroughView() }', '{ AppWalkthroughView(app: app) }', 1)
expected = expected.replace('    var size: CGFloat = 30\n', '    var size: CGFloat = 30\n    var tiltedO = false\n', 1)
expected = expected.replace('            Text("Harbor").font(wordmarkFont).tracking(-1)', '''            if tiltedO {
                HStack(spacing: 0) {
                    Text("Harb")
                    Text("o").rotationEffect(.degrees(7), anchor: UnitPoint(x: 0.5, y: 0.65))
                    Text("r")
                }.font(wordmarkFont).tracking(-1)
            } else { Text("Harbor").font(wordmarkFont).tracking(-1) }''', 1)
assert text('HEAD', name) == expected, 'The normal shell or navigation behavior changed'
name = 'ios/Harbor/Views/ProfileEditor.swift'
expected = text(previous, name).replace('Text(profile.value.name.isEmpty ? app.user?.displayName ?? "Invitado" : profile.value.name)', 'accountName(profile)', 1)
expected = expected.replace('.accessibilityLabel(DesktopInterfaceText.value("Account")).accessibilityIdentifier("main-account")', '.accessibilityLabel(DesktopInterfaceText.value("Account")).accessibilityValue(accountName(profile)).accessibilityIdentifier("main-account")', 1)
expected = expected.replace('\n}\n\nstruct ProfileEditor:', '''
    private func accountName(_ profile: ProfilePreferences) -> Text {
        if !profile.value.name.isEmpty { return Text(verbatim: profile.value.name) }
        if let user = app.user { return Text(verbatim: user.displayName) }
        return Text("Guest")
    }
}

struct ProfileEditor:''', 1)
assert text('HEAD', name) == expected, 'Only localize the default guest label; preserve user names and profile writes'
name = 'ios/Harbor/Views/SystemAboutView.swift'
assert text('HEAD', name) == text(previous, name).replace('.navigationTitle(DesktopInterfaceText.value("About"))', '.navigationTitle(DesktopInterfaceText.value("About")).navigationBarTitleDisplayMode(.inline)', 1)
name = 'ios/Harbor/Views/SystemStorageView.swift'
expected = text(previous, name).replace('.navigationTitle(DesktopInterfaceText.value("Storage overview"))', '.navigationTitle(DesktopInterfaceText.value("Storage overview")).navigationBarTitleDisplayMode(.inline)', 1)
expected = expected.replace('ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)', 'bytes <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)', 1)
assert text('HEAD', name) == expected, 'The storage scan and cache maintenance operations must remain unchanged'
name = 'ios/Harbor/Services/DiscoveryPreferences.swift'
after = text('HEAD', name)
addition = after.split('    @discardableResult func seedTaste(', 1)[1].split('    func isQueueItemHidden(', 1)[0]
assert after.replace('    @discardableResult func seedTaste(' + addition, '', 1) == text(previous, name), 'Previously approved voting/queue behavior changed'
name = 'ios/Harbor/ViewModels/HomeContentModel.swift'
before, after = (text(ref, name) for ref in [previous, 'HEAD'])
assert before.split('    func load(app:', 1)[0] == after.split('    func load(app:', 1)[0], 'Anime loading changed'
marker = '            if !rows.contains(where: { !$0.metas.isEmpty }) {'
assert before.split(marker, 1)[1] == after.split(marker, 1)[1], 'Existing Cinemeta fallback, hero enrichment or fixed definitions changed'
name = 'ios/Harbor/Views/InterfaceSettingsView.swift'
pattern = r'^struct NavigationSettingsView:.*?(?=^(?:private )?struct HomeStylePicker:)'
assert re.search(pattern, text(previous, name), re.S | re.M).group() == re.search(pattern, text('HEAD', name), re.S | re.M).group(), 'The approved account-scoped navigation editor changed'
name = 'ios/Harbor/Views/DiscoveryRails.swift'
addition = '''            else if let service = StreamingServiceDefinition.all.first(where: { rail.path == "streaming:" + $0.key }) {
                next = try await StreamingCatalog.page(service, page: page, configuration: MetadataPreferences.shared.configuration())
            }
'''
assert text('HEAD', name).replace(addition, '', 1) == text(previous, name), 'Existing catalog/anime pagination changed'
name = 'ios/Harbor/DesktopLanguages.json'
before, after = (json.loads(text(ref, name)) for ref in [previous, 'HEAD'])
assert [{key: item[key] for key in ['code', 'nativeLabel']} for item in after] == before
assert [item['code'] for item in after] == codes and all(isinstance(item['rtl'], bool) and item['greeting'] and item['label'] for item in after)

def strings(value): return {json.loads(key): json.loads(label) for key, label in re.findall(r'^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$', value, re.M)}
for code in codes:
    name = f'ios/Harbor/{code}.lproj/Localizable.strings'
    old, new = (strings(text(ref, name)) for ref in [previous, 'HEAD'])
    assert old and all(new.get(key) == value for key, value in old.items()), 'Approved native labels changed: ' + code
name = 'ios/Harbor/NativeInterfaceTranslations.json'
old, new = (json.loads(text(ref, name)) for ref in [previous, 'HEAD'])
assert all(all(new[code].get(key) == value for key, value in values.items()) for code, values in old.items())

tests = {
    'ios/HarborTests/OnboardingContentTests.swift', 'ios/HarborTests/StreamingPreferencesTests.swift',
    'ios/HarborIntegrationTests/OnboardingLiveTests.swift', 'ios/HarborUITests/OnboardingNavigationTests.swift',
    'ios/HarborUITests/SystemMaintenanceNavigationTests.swift',
    'ios/HarborUITests/LanguageReferenceNavigationTests.swift',
}
assert changed(['ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests']) == tests
name = 'ios/HarborUITests/SystemMaintenanceNavigationTests.swift'
marker = '        capture(app, name: "system-about-" + device)\n'
assert text(previous, name).split(marker, 1)[0] == text('HEAD', name).split(marker, 1)[0], 'Preserved storage/About UI steps changed'
new_tests = tests - {name, 'ios/HarborUITests/LanguageReferenceNavigationTests.swift'}
assert sum(len(re.findall(r'\bfunc test\w+\(', text('HEAD', name))) for name in new_tests) == 12
proof = dict(source=os.environ.get('GITHUB_SHA'), previous_source=previous, scope='onboarding-desktop',
             local_source_review_only=a.working_tree, prior_evidence_verified=False, expected_actual_executions=16,
             native_methods=9, public_integration_methods=1, ui_methods=6, required_new_images=30, transient_splash_images_up_to=2,
             required_recordings=['setup-iphone.mp4', 'setup-ipad.mp4'],
             ipa_created=False, full_desktop_parity_complete=False, physical_device_validation=False)
if not a.working_tree:
    run_ids = os.environ.get('HARBOR_PREVIOUS_RUNS', '').split(',')
    assert run_ids and all(re.fullmatch('[0-9]+', run) for run in run_ids)
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-onboarding-validation'}
    api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
    candidates = [get('/actions/runs/' + run) for run in run_ids]
    approved = [run for run in candidates if run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] == 'success']
    assert len(approved) == 1, 'Require actual successful validation of the preserved navigation source'
    run = approved[0]
    jobs = get(f'/actions/runs/{run["id"]}/jobs?per_page=100')['jobs']
    job = next(job for job in jobs if job['name'] == 'Apple SDK / Swift / iPhone')
    assert job['conclusion'] == 'success'
    steps = {step['name']: step['conclusion'] for step in job['steps']}
    assert all(steps[name] == 'success' for name in ['Build simulator', 'Run bridge and model tests on iPhone simulator', 'Run native UI on the selected simulator', 'Run affected navigation customization on iPad'])
    assert all(steps[name] == 'skipped' for name in ['Build device without signing', 'Package and verify unsigned iPhone IPA', 'Save verified unsigned IPA in a draft Release'])
    # Actual test evidence must also be verified before preserving a green job.
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
    assert len(outcomes) == 27 and all(row[2] == 'passed' for row in outcomes)
    assert len({row[:2] for row in outcomes}) == 27
    affected_ui = {'HarborUITests.SystemMaintenanceNavigationTests', 'HarborUITests.LanguageReferenceNavigationTests'}
    preserved = ['/'.join(row[:2]) for row in outcomes if row[0] not in affected_ui]
    revalidated = ['/'.join(row[:2]) for row in outcomes if row[0] in affected_ui]
    assert len(preserved) == 23 and len(revalidated) == 4
    proof.update(prior_evidence_verified=True, preserved_navigation_run=run['id'], preserved_actual_cases=preserved,
                 affected_previously_passed_cases_revalidated=revalidated,
                 reason_for_ui_revalidation='Actual captures showed oversized system navigation titles and an untranslated default guest label. Only the four UI cases rendering those changed elements are revalidated; native maintenance and navigation logic remain intact.',
                 previous_job_log_sha256=hashlib.sha256(data).hexdigest(),
                 replaced_historical_four_page_walkthrough=True, preserved_storage_about_prefix=True)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Onboarding source scope reviewed; ' + ('Apple validation pending.' if a.working_tree else 'actual prior approved results preserved.'))

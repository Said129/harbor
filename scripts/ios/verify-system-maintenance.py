"""Preserve approved unchanged behavior before native system maintenance checks."""
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
previous = 'c78569d6a1579b3cca2f4c736c5b66de7f96f119'
subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', previous], check=True)
codes = ['en', 'ar', 'zh', 'fr', 'de', 'hi', 'id', 'it', 'ja', 'ko', 'pl', 'pt', 'ru', 'es', 'tr', 'vi']
allowed = {
    'ios/Harbor/NativeInterfaceTranslations.json',
    'ios/Harbor/Services/ArtworkStore.swift', 'ios/Harbor/Services/AppStorageMaintenance.swift',
    'ios/Harbor/Services/AppGuidePreferences.swift',
    'ios/Harbor/Views/SystemStorageView.swift', 'ios/Harbor/Views/SystemAboutView.swift',
    'ios/Harbor/Views/AppWalkthroughView.swift', 'ios/Harbor/Views/SettingsView.swift',
    'ios/Harbor/Views/DesktopInterfaceText.swift', 'ios/Harbor/Views/HarborShell.swift',
    'ios/Harbor/ViewModels/AppModel.swift', 'ios/project.yml',
    'ios/Harbor/Views/SidebarNavigationIcon.swift', 'ios/Harbor/Services/InterfacePreferences.swift',
    'ios/Harbor/Views/InterfaceSettingsView.swift', 'ios/Harbor/DesktopAnimations/LICENSE-Harbor.txt',
}
animation_manifest = json.loads(Path('docs/ios/desktop-navigation-animations-0.9.132.json').read_text('utf-8'))
allowed.update('ios/Harbor/DesktopAnimations/nav/' + item['name'] + '.json' for item in animation_manifest['animations'])
allowed.update(f'ios/Harbor/{code}.lproj/Localizable.strings' for code in codes)
roots = ['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']
changed = set(subprocess.check_output(['git', 'diff', '--name-only', previous, 'HEAD', '--', *roots], text=True).splitlines())
assert changed == allowed, 'Validate any application change beyond the reviewed system scope'

def blob(ref, name): return subprocess.check_output(['git', 'show', ref + ':' + name]).decode('utf-8')

name = 'ios/Harbor/ViewModels/AppModel.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
assert after == before.replace('                addons = account.collection.addons\n', '                addons = account.collection.addons\n                AppGuidePreferences.shared.prepare(hasSavedConfiguration: true)\n', 1).replace(
    '            else if let saved = try keychain.read("addons.v1", as: [Addon].self) { addons = saved }\n            else {\n',
    '            else if let saved = try keychain.read("addons.v1", as: [Addon].self) {\n                addons = saved\n                AppGuidePreferences.shared.prepare(hasSavedConfiguration: true)\n            }\n            else {\n                AppGuidePreferences.shared.prepare(hasSavedConfiguration: false)\n', 1)
name = 'ios/Harbor/Views/HarborShell.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
sheet = '''            .sheet(isPresented: Binding(get: {
                app.storageReady && document == nil && !app.showAccount && AppGuidePreferences.shared.presentationRequested
            }, set: { if !$0 { AppGuidePreferences.shared.finish() } })) { AppWalkthroughView() }
'''
expected_shell = before.replace('    @State private var menu = false\n', '    @State private var menu = false\n    @State private var hoveredSection: HarborSection?\n    @Environment(\\.accessibilityReduceMotion) private var reduceMotion\n', 1)
expected_shell = expected_shell.replace('Image("nav-\\(item.icon)").resizable().scaledToFit().frame(width: 23, height: 23)', 'SidebarNavigationIcon(section: item, hovered: hoveredSection == item, tint: item == section ? HarborTheme.ink : HarborTheme.ink.opacity(0.65))', 1)
expected_shell = expected_shell.replace('                                }.buttonStyle(.plain).accessibilityIdentifier("nav-\\(item.rawValue)")', '                                        .onHover { hovering in if hovering { hoveredSection = item } else if hoveredSection == item { hoveredSection = nil } }\n                                }.buttonStyle(HarborNavigationButtonStyle()).accessibilityIdentifier("nav-\\(item.rawValue)")', 1)
expected_shell = expected_shell.replace('withAnimation(.easeOut(duration: 0.18))', 'withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18))')
expected_shell = expected_shell.replace('private func closeMenu() { withAnimation', 'private func closeMenu() { hoveredSection = nil; withAnimation', 1)
assert after.count(sheet) == 1 and after.replace(sheet, '', 1) == expected_shell
name = 'ios/Harbor/Services/InterfacePreferences.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
addition = '    var navIconAnimations = UserDefaults.standard.object(forKey: "navIconAnimations") as? Bool ?? true { didSet { storage.set(navIconAnimations, forKey: "navIconAnimations") } }\n'
assert after == before.replace('    private let storage = UserDefaults.standard\n', '    private let storage = UserDefaults.standard\n' + addition, 1)
name = 'ios/Harbor/Views/InterfaceSettingsView.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
addition = '                    HarborSettingsToggle(DesktopInterfaceText.value("Animated sidebar icons"), note: DesktopInterfaceText.value("Sidebar icons animate when pressed or hovered with a pointer. Turn this off to keep them static."), isOn: $preferences.navIconAnimations)\n'
assert after.count(addition) == 1 and after.replace(addition, '', 1) == before
for item in animation_manifest['animations']:
    assert hashlib.sha256(blob('HEAD', 'ios/Harbor/DesktopAnimations/nav/' + item['name'] + '.json').encode()).hexdigest() == item['sha256']
name = 'ios/project.yml'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
expected_project = before.replace('    revision: 22787ffb59de99e5dc1fbfe80b19c97a904ad48d\n', '    revision: 22787ffb59de99e5dc1fbfe80b19c97a904ad48d\n  Lottie:\n    url: https://github.com/airbnb/lottie-spm.git\n    revision: 0aff16288f8dc1e3dab35cbf5cf45979673fd3df\n', 1)
expected_project = expected_project.replace('        excludes: [HarborLoader]', '        excludes: [HarborLoader, DesktopAnimations]', 1)
expected_project = expected_project.replace('      - path: Harbor/HarborLoader\n        type: folder\n        buildPhase: resources\n', '      - path: Harbor/HarborLoader\n        type: folder\n        buildPhase: resources\n      - path: Harbor/DesktopAnimations\n        type: folder\n        buildPhase: resources\n', 1)
expected_project = expected_project.replace('      - package: ZIPFoundation\n        product: ZIPFoundation\n', '      - package: ZIPFoundation\n        product: ZIPFoundation\n      - package: Lottie\n        product: Lottie\n', 1)
expected_project = expected_project.replace('    dependencies:\n      - target: Harbor\n', '    dependencies:\n      - target: Harbor\n      - package: Lottie\n        product: Lottie\n', 1)
assert after == expected_project, 'Only the pinned animation renderer and resource folder may change the project'
marker = '/// Shared loading prevents a hero'
name = 'ios/Harbor/Services/ArtworkStore.swift'
old_tail, new_tail = (blob(ref, name).split(marker, 1)[1] for ref in [previous, 'HEAD'])
assert old_tail == new_tail, 'Existing artwork rendering and downsampling must remain unchanged'

def strings(value):
    return {json.loads(key): json.loads(text) for key, text in re.findall(r'^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$', value, re.M)}

for code in codes:
    name = f'ios/Harbor/{code}.lproj/Localizable.strings'
    old, new = (strings(blob(ref, name)) for ref in [previous, 'HEAD'])
    assert old and all(new.get(key) == value for key, value in old.items()), f'Existing {code} language text changed'
name = 'ios/Harbor/NativeInterfaceTranslations.json'
before, after = (json.loads(blob(ref, name)) for ref in [previous, 'HEAD'])
assert all(all(after[code].get(key) == value for key, value in labels.items()) for code, labels in before.items())

tests = {
    'ios/HarborTests/SystemStorageTests.swift', 'ios/HarborTests/ArtworkMaintenanceTests.swift',
    'ios/HarborTests/AppGuideTests.swift', 'ios/HarborUITests/SystemMaintenanceNavigationTests.swift',
    'ios/HarborTests/NavigationAnimationTests.swift', 'ios/HarborTests/Fixtures/navigation-animation-hashes.json',
    'ios/HarborUITests/LanguageReferenceNavigationTests.swift',
}
name = 'ios/HarborUITests/LanguageReferenceNavigationTests.swift'
before, after = (blob(ref, name) for ref in [previous, 'HEAD'])
assert after == before.replace('app.launchArguments = ["-uiLanguage", "es"]', 'app.launchArguments = ["-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]', 1), 'Only remove the forced-language argument and use ordinary completed-guide preferences'
test_roots = ['ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests']
assert set(subprocess.check_output(['git', 'diff', '--name-only', previous, 'HEAD', '--', *test_roots], text=True).splitlines()) == tests
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-system-maintenance'}
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
with urllib.request.urlopen(urllib.request.Request(api + '/actions/runs/39028548982', headers=headers), timeout=45) as response:
    run = json.load(response)
assert run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] == 'failure'
with urllib.request.urlopen(urllib.request.Request(api + '/actions/runs/39028548982/jobs?per_page=100', headers=headers), timeout=45) as response:
    jobs = json.load(response)['jobs']
job = next(item for item in jobs if item['id'] == 117384252565)
steps = {step['name']: step['conclusion'] for step in job['steps']}
assert steps['Build simulator'] == steps['Run bridge and model tests on iPhone simulator'] == 'success'
assert steps['Run native UI on the selected simulator'] == 'failure'
assert steps['Run the expanded reference language UI on iPad'] == 'skipped'
assert all(steps[name] == 'skipped' for name in ['Build device without signing', 'Package and verify unsigned iPhone IPA', 'Save verified unsigned IPA in a draft Release'])

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, response_headers, new_url): return None

try:
    logs = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(api + '/actions/jobs/117384252565/logs', headers=headers), timeout=45)
except urllib.error.HTTPError as redirect:
    if redirect.code != 302: raise
    location = redirect.headers['Location']
    parsed = urllib.parse.urlparse(location)
    assert parsed.scheme == 'https' and parsed.hostname
    # Never forward the GitHub credential to temporary log storage.
    logs = urllib.request.urlopen(location, timeout=45)
with logs: log_bytes = logs.read(32 * 1024 * 1024 + 1)
assert len(log_bytes) <= 32 * 1024 * 1024
log = log_bytes.decode('utf-8', errors='replace')
outcomes = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", log)
approved = ('HarborTests.StableMobileTests', 'testDesktopLanguagesAndNativeFeedbackUseTheSelectedCatalog', 'passed')
reviewed_failure = ('HarborUITests.LanguageReferenceNavigationTests', 'testReferenceLanguagesSwitchInTheOrdinaryIPhoneSettings', 'failed')
assert outcomes == [approved, reviewed_failure], 'Preserve only the actual approved native language case; both UI methods still need execution'
guards = {}
for row in subprocess.check_output(['git', 'ls-tree', '-r', 'HEAD', '--', *roots], text=True).splitlines():
    identity, name = row.split('\t', 1)
    if name not in allowed: guards[name] = identity
proof = dict(source=os.environ['GITHUB_SHA'], previous_source=previous, previous_run=39028548982,
             unchanged_git_blobs=guards, unchanged_artwork_render_tail_sha256=hashlib.sha256(new_tail.encode()).hexdigest(),
             actual_affected_selection=['SystemStorageTests', 'ArtworkMaintenanceTests', 'AppGuideTests', 'NavigationAnimationTests', 'SystemMaintenanceNavigationTests'],
             preserved_native_language_case='/'.join(approved[:2]), previous_log_sha256=hashlib.sha256(log_bytes).hexdigest(),
             prior_run_conclusion='failure', prior_reviewed_failure='/'.join(reviewed_failure[:2]),
             pending_language_ui=['testReferenceLanguagesSwitchInTheOrdinaryIPhoneSettings', 'testReferenceLanguagesSwitchInTheOrdinaryIPadSettings'],
             scope='System storage measurement, image-cache maintenance, About, native walkthrough state, Desktop variable interpolation and original navigation animations. Existing locale values, account/addon operations, playback, reading, sources, Rust and bundle identity remain unchanged. Run affected native methods and ordinary system UI on iPhone/iPad only.',
             full_desktop_parity_complete=False, visual_parity_audit_complete=False, physical_device_validation=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Preserved approved unchanged cases; only affected system and image-cache checks execute. No IPA.')

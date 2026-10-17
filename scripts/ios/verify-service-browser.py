"""Review the service browser scope while preserving approved setup and playback."""
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
p.add_argument('--working-tree', action='store_true')
a = p.parse_args()
assert not (a.working_tree and os.environ.get('GITHUB_ACTIONS'))
previous = os.environ.get('HARBOR_PREVIOUS_SOURCE') or 'e9592c4b18eaea6698a7f5dac5de02a0822fd4b2'
assert re.fullmatch('[a-f0-9]{40}', previous)
if subprocess.run(['git', 'cat-file', '-e', previous + '^{commit}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
    subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', previous], check=True)

def blob(ref, name):
    if a.working_tree and ref == 'HEAD': return Path(name).read_text('utf-8').replace('\r\n', '\n')
    return subprocess.check_output(['git', 'show', ref + ':' + name]).decode('utf-8')

def changes(roots):
    command = ['git', 'diff', '--name-only', previous] + ([] if a.working_tree else ['HEAD']) + ['--', *roots]
    result = set(subprocess.check_output(command, text=True).splitlines())
    if a.working_tree: result.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *roots], text=True).splitlines())
    return result

codes = ['en', 'ar', 'zh', 'fr', 'de', 'hi', 'id', 'it', 'ja', 'ko', 'pl', 'pt', 'ru', 'es', 'tr', 'vi']
allowed = {'ios/Harbor/Services/ServiceCatalogModel.swift', 'ios/Harbor/Views/StreamingCatalogView.swift',
           'ios/Harbor/Views/StreamingSettingsView.swift', 'ios/Harbor/Views/DiscoveryRails.swift', 'ios/Harbor/NativeInterfaceTranslations.json'}
allowed.update(f'ios/Harbor/{code}.lproj/Localizable.strings' for code in codes)
assert changes(['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']) == allowed, 'Review any change outside the new service browser, additive labels and its two entry points'
name = 'ios/Harbor/Views/DiscoveryRails.swift'
expected = blob(previous, name)
needle = '    var body: some View {\n        ScrollView {\n            LazyVStack(spacing: 18) {'
assert expected.count(needle) == 1
expected = expected.replace(needle, '''    var body: some View {
        if let service = StreamingServiceDefinition.all.first(where: { rail.path == "streaming:" + $0.key }) {
            StreamingCatalogView(service: service, app: app)
        } else { grid }
    }
    private var grid: some View {
        ScrollView {
            LazyVStack(spacing: 18) {''', 1)
expected = expected.replace('''            else if let service = StreamingServiceDefinition.all.first(where: { rail.path == "streaming:" + $0.key }) {
                next = try await StreamingCatalog.page(service, page: page, configuration: MetadataPreferences.shared.configuration())
            }
''', '', 1)
assert blob('HEAD', name) == expected, 'Existing non-service grids and pagination must remain unchanged'
name = 'ios/Harbor/Views/StreamingSettingsView.swift'
expected = blob(previous, name).replace('                StreamingServicePicker(preferences: StreamingPreferences.forOwner(app.user?.id ?? "guest"))\n', '''                StreamingServicePicker(preferences: StreamingPreferences.forOwner(app.user?.id ?? "guest"))
                NavigationLink { StreamingServicesView(app: app) } label: {
                    Label(DesktopInterfaceText.value("Browse services"), systemImage: "square.grid.3x3").frame(minHeight: 44)
                }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("streaming-browse-services")
''', 1)
expected = expected.replace('    let service: StreamingServiceDefinition\n', '    let service: StreamingServiceDefinition\n    var height: CGFloat = 22\n    var horizontalPadding: CGFloat = 12\n', 1)
expected = expected.replace('.frame(maxWidth: 110, maxHeight: service.logoHeight).padding(.horizontal, 12)', '.frame(maxWidth: height * 5, maxHeight: CGFloat(service.logoHeight) * height / 22).padding(.horizontal, horizontalPadding)', 1)
assert blob('HEAD', name) == expected, 'Keep the approved picker and its default logo geometry intact'

def strings(value): return {json.loads(key): json.loads(text) for key, text in re.findall(r'^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$', value, re.M)}
for code in codes:
    name = f'ios/Harbor/{code}.lproj/Localizable.strings'
    old, new = (strings(blob(ref, name)) for ref in [previous, 'HEAD'])
    assert all(new.get(key) == value for key, value in old.items()), 'Previously approved labels changed: ' + code
name = 'ios/Harbor/NativeInterfaceTranslations.json'
old, new = (json.loads(blob(ref, name)) for ref in [previous, 'HEAD'])
assert all(all(new[code].get(key) == value for key, value in values.items()) for code, values in old.items())
messages = {'Browse services', 'Add your TMDB key in Settings to load these catalogs.', 'Could not load this page. Try again.'}
assert all(all(isinstance(new[code].get(key), str) and new[code][key] for key in messages) for code in codes)
tests = {'ios/HarborTests/ServiceCatalogTests.swift', 'ios/HarborUITests/ServiceCatalogNavigationTests.swift'}
assert changes(['ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests']) == tests
assert sum(len(re.findall(r'\bfunc test\w+\(', blob('HEAD', name))) for name in tests) == 7
proof = dict(source=os.environ.get('GITHUB_SHA'), previous_source=previous, scope='service-browser',
             local_source_review_only=a.working_tree, prior_evidence_verified=False, expected_actual_executions=7,
             native_methods=5, ui_methods=2, expected_new_images=6, ipa_created=False,
             required_recordings=['service-iphone.mp4', 'service-ipad.mp4'],
             personal_tmdb_account_test=False, full_desktop_parity_complete=False, physical_device_validation=False)
if not a.working_tree:
    api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-service-browser-validation'}
    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
    ids = os.environ['HARBOR_PREVIOUS_RUNS'].split(','); assert all(re.fullmatch('[0-9]+', value) for value in ids)
    runs = [get('/actions/runs/' + value) for value in ids]
    approved = [run for run in runs if run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] == 'success']
    assert len(approved) == 1, 'Require actual completed setup validation before preserving it'
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
    assert len(outcomes) == 16 and len({row[:2] for row in outcomes}) == 16 and all(row[2] == 'passed' for row in outcomes)
    proof.update(prior_evidence_verified=True, preserved_setup_run=run['id'], preserved_actual_cases=['/'.join(row[:2]) for row in outcomes], previous_job_log_sha256=hashlib.sha256(data).hexdigest())
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Service browser source scope reviewed; ' + ('Apple validation pending.' if a.working_tree else 'actual approved setup outcomes preserved.'))

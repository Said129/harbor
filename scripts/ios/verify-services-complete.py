"""Preserve individual passed cases and validate new services plus setup repairs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--working-tree', action='store_true')
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
assert not (a.working_tree and os.environ.get('GITHUB_ACTIONS'))
previous = os.environ.get('HARBOR_PREVIOUS_SOURCE') or 'e9592c4b18eaea6698a7f5dac5de02a0822fd4b2'
intermediate = '9a68eb118f6304301d7a96560f2b9409897d0f87'
sync_source = '1b50d894735fa48e738591a0a0e83aac488ac1cb'
assert re.fullmatch('[a-f0-9]{40}', previous)
a.output.parent.mkdir(parents=True, exist_ok=True)
source = os.environ.get('GITHUB_SHA')
first = a.output.with_name('preserved-service-source-slice.json')
second = a.output.with_name('preserved-streaming-source-slice.json')
env = dict(os.environ, HARBOR_PREVIOUS_SOURCE=previous, HARBOR_CURRENT_SOURCE=intermediate, GITHUB_SHA=intermediate)
subprocess.run([sys.executable, 'scripts/ios/verify-service-browser.py', '--source-review-only', '--output', str(first)], env=env, check=True)
env = dict(os.environ, HARBOR_PREVIOUS_SOURCE=intermediate, HARBOR_CURRENT_SOURCE=sync_source, GITHUB_SHA=sync_source)
command = [sys.executable, 'scripts/ios/verify-streaming-sync.py', '--source-review-only', '--output', str(second)]
subprocess.run(command, env=env, check=True)
slices = [json.loads(path.read_text('utf-8')) for path in [first, second]]
assert all(value['prior_evidence_verified'] is False and value['intermediate_source_review_only'] is True for value in slices)
assert slices[0]['source'] == intermediate and slices[0]['previous_source'] == previous
assert slices[1]['previous_source'] == intermediate
def blob(ref, name):
    if a.working_tree and ref == 'HEAD': return Path(name).read_text('utf-8').replace('\r\n', '\n')
    return subprocess.check_output(['git', 'show', ref + ':' + name]).decode('utf-8')
def changes(roots):
    command = ['git', 'diff', '--name-only', sync_source] + ([] if a.working_tree else ['HEAD']) + ['--', *roots]
    result = set(subprocess.check_output(command, text=True).splitlines())
    if a.working_tree: result.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *roots], text=True).splitlines())
    return result
assert changes(['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']) == {'ios/Harbor/Views/OnboardingSteps.swift', 'ios/Harbor/Views/StreamingCatalogView.swift'}
name = 'ios/Harbor/Views/OnboardingSteps.swift'
expected = blob(sync_source, name)
expected = expected.replace('''                Label(DesktopInterfaceText.value(app.user == nil ? "Sign in" : "Manage"), image: "account-stremio").frame(minHeight: 44)''', '''                Label { Text(DesktopInterfaceText.value(app.user == nil ? "Sign in" : "Manage")) } icon: {
                    Image("account-stremio").resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                }.frame(minHeight: 44)''', 1)
expected = expected.replace('''                            Artwork(url: media.poster, maxPixels: 360).aspectRatio(2.0 / 3, contentMode: .fit)
                                .overlay {
                                    Color.black.opacity(selected ? 0.45 : 0)
                                    Image("onboarding-thumbsup").resizable().scaledToFit().padding(22).shadow(radius: 5)
                                        .scaleEffect(selected ? 1 : 0.75).opacity(selected ? 1 : 0)
                                }.clipShape(.rect(cornerRadius: 12)).opacity(atLimit ? 0.4 : 1)''', '''                            ZStack {
                                Rectangle().fill(HarborTheme.surface)
                                Artwork(url: media.poster, maxPixels: 360)
                                Color.black.opacity(selected ? 0.45 : 0).allowsHitTesting(false)
                                Image("onboarding-thumbsup").resizable().scaledToFit().padding(22).shadow(radius: 5)
                                    .scaleEffect(selected ? 1 : 0.75).opacity(selected ? 1 : 0).allowsHitTesting(false).accessibilityHidden(true)
                            }.aspectRatio(2.0 / 3, contentMode: .fit)
                                .clipShape(.rect(cornerRadius: 12)).contentShape(.rect(cornerRadius: 12)).opacity(atLimit ? 0.4 : 1)''', 1)
assert blob('HEAD', name) == expected, 'Only repair the taste hit area and the overflowing account icon'
name = 'ios/Harbor/Views/StreamingCatalogView.swift'
expected = blob(sync_source, name).replace('''                            Label(DesktopInterfaceText.value("Connect TMDB"), image: "metadata-tmdb")''', '''                            Label { Text(DesktopInterfaceText.value("Connect TMDB")) } icon: {
                                Image("metadata-tmdb").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                            }''', 1)
assert blob('HEAD', name) == expected, 'Keep catalog behavior and animations unchanged while bounding the metadata icon'
assert changes(['ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests']) == {'ios/HarborUITests/OnboardingNavigationTests.swift'}
affected = ['HarborTests.StreamingPreferencesTests/testOwnerIsolationPersistenceAndFailedWritesKeepThePublishedSelection', 'HarborTests.StreamingPreferencesTests/testUnreadablePreferencesCannotBeOverwrittenByFallbackDefaults']
proof = dict(source=source, previous_source=previous, scope='services-complete', local_source_review_only=a.working_tree,
             prior_evidence_verified=False, intermediate_source_review_only=True, source_slices=slices,
             expected_actual_executions=29, new_native_methods=18, affected_existing_native_methods=2, unverified_live_methods=1,
             ui_methods=8, expected_new_images_minimum=34, optional_transient_images=2,
             required_recordings=['service-iphone.mp4', 'service-ipad.mp4'],
             prior_evidence_kind='individual-passed-cases-from-terminal-run', affected_existing_cases_revalidated=affected,
             ipa_created=False, physical_device_validation=False, complete_multi_profile_ui=False,
             full_desktop_parity_complete=False)
if not a.working_tree:
    api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-combined-service-validation'}
    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response: return json.load(response)
    ids = os.environ['HARBOR_PREVIOUS_RUNS'].split(','); assert all(re.fullmatch('[0-9]+', value) for value in ids)
    runs = [get('/actions/runs/' + value) for value in ids]
    approved = [run for run in runs if run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] in ['success', 'failure']]
    assert len(approved) == 1, 'Require the terminal run containing the individual passed cases'
    run = approved[0]
    job = next(job for job in get(f'/actions/runs/{run["id"]}/jobs?per_page=100')['jobs'] if job['name'] == 'Apple SDK / Swift / iPhone')
    assert job['conclusion'] in ['success', 'failure']
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, file, code, message, response_headers, new_url): return None
    try: response = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers), timeout=45)
    except urllib.error.HTTPError as redirect:
        if redirect.code != 302: raise
        location = redirect.headers['Location']; assert urllib.parse.urlparse(location).scheme == 'https'
        response = urllib.request.urlopen(location, timeout=45)
    with response: data = response.read(32 * 1024 * 1024 + 1)
    assert len(data) <= 32 * 1024 * 1024
    expected = set()
    for suite, folder in [('OnboardingContentTests', 'HarborTests'), ('StreamingPreferencesTests', 'HarborTests')]:
        content = subprocess.check_output(['git', 'show', previous + ':ios/' + folder + '/' + suite + '.swift']).decode('utf-8')
        expected.update(folder + '.' + suite + '/' + name for name in re.findall(r'\bfunc (test\w+)\(', content))
    expected.update(['HarborUITests.LanguageReferenceNavigationTests/testReferenceLanguagesSwitchInTheOrdinaryIPhoneSettings', 'HarborUITests.SystemMaintenanceNavigationTests/testStorageAndAboutWorkInTheOrdinaryIPhoneInterface'])
    outcomes = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(", data.decode('utf-8', errors='replace'))
    for case in expected:
        matching = [row for row in outcomes if row[0] + '/' + row[1] == case]
        assert len(matching) == 1 and matching[0][2] == 'passed', 'Do not preserve a failed, skipped, unfinished or duplicate case: ' + case
    assert len(expected) == 11
    proof.update(prior_evidence_verified=True, preserved_partial_setup_run=run['id'], prior_run_conclusion=run['conclusion'],
                 verified_individual_passed_cases=sorted(expected), reused_unchanged_cases=sorted(expected - set(affected)),
                 previous_job_log_sha256=hashlib.sha256(data).hexdigest(),
                 unverified_live_case='HarborIntegrationTests.OnboardingLiveTests/testNativeTasteSetupLoadsActualPublicTitlesWithCoversWithoutBundledKeys')
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Service slices and setup repairs reviewed; ' + ('Apple execution pending.' if a.working_tree else 'nine unchanged passed cases preserved, two affected cases revalidated; 29 executions required.'))

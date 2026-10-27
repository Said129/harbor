"""Trakt authorization/readback plus affected merge and the unexecuted phone UI."""
import json
import os
from pathlib import Path
import re

block = 'trakt-account'
marker = 'affected:' + block
cases = []
for suite, count in [('TraktAccountTests', 9), ('TraktAccountMountTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = [
    'HarborTests.SimklPlaybackImportTests/testProductionLibraryMergesImportedCardsWithoutSavingThemInStremioAndDismissalSurvivesRefresh',
    'HarborTests.ContinuePrivacyTests/testPrivateProjectionAndResumeExcludeNewerSharedCloudAndOtherProfilesAndKeepDismissalsSeparate',
]
cases += affected
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
seed = 'HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource'
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='TraktSources' + family, family=family, seed=seed,
        cases=['HarborExistingAppUITests.TraktSourcesNavigationTests/testActualTraktSourceControlPersistsAndRemainsDisconnectedWithoutProviderCredentialsOn' + family]))
    captures += ['trakt-source-' + state + '-' + family.lower() for state in ['off', 'enabled', 'restored']]
phone = 'HarborExistingAppUITests.ContinuePrivacyNavigationTests/testActualPrivateChoiceLocksSharedSourcesKeepsDownloadsEditableAndRestoresAllChoicesOnIPhone'
batches.append(dict(id='ContinuePrivacyPendingIPhone', family='IPhone', seed=seed, cases=[phone]))
captures += ['continue-private-' + state + '-iphone' for state in ['default', 'locked', 'restored', 'unlocked']]
captures += ['trakt-native-' + state + '-' + size for size in ['compact', 'regular'] for state in ['disconnected', 'connected', 'code', 'denied', 'card']]
for case in cases + [item for batch in batches for item in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(cases) == len(set(cases)) == 12 and len(captures) == len(set(captures)) == 20
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=12, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=3, expected_total_executions=18,
    expected_original_images=20, required_original_captures=captures,
    new_native_cases=10, affected_merge_cases=affected, unexecuted_phone_ui_only=True,
    original_reference='ios/HarborTests/Fixtures/trakt-account-reference.json',
    original_playback_cases=28, original_auth_cases=7, provider_account_requests=False,
    unresolved_native_focus_repeated=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False,
    physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('10 new native +2 affected merges +3 fresh owned guests +3 real UI=18 executions/20 captures. No IPA; retain unrelated approved cases.')

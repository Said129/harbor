"""Only new playback, affected account lineage/copy/asset and the pending phone privacy route."""
import json
import os
from pathlib import Path
import re

block = 'trakt-scrobble'
marker = 'affected:' + block
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/TraktScrobbleTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 10
cases = ['HarborTests.TraktScrobbleTests/' + method for method in methods]
affected = [
    'HarborTests.TraktAccountTests/testAccountPersistenceCommitsBeforePublishingAndNeverClearsAnotherProfile',
    'HarborTests.TraktAccountTests/testConcurrentUnauthorizedRequestsShareOneRefreshAnd429RetriesStayBounded',
    'HarborTests.TraktAccountTests/testHeldRefreshPersistsOnlyItsStillOwnedAccountAndNeverRestoresADisconnectedSession',
    'HarborTests.TraktAccountTests/testCancelledAuthorizationAndChangedProfileCannotPublishAnInFlightGrant',
    'HarborTests.LocalSourceMigrationTests/testEveryDesktopLanguageHasAccountIndependentSourceAndPrivateHistoryGuidance',
    'HarborTests.TraktAccountMountTests/testActualSettingsAuthorizationFailureAndDecodedContinuationRenderInBothNativeLayouts',
]
cases += affected
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
seed = 'HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource'
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='HarborAccountNote' + family, family=family, seed=seed,
        cases=['HarborExistingAppUITests.HarborAccountNoteNavigationTests/testActualHarborServerNoteFollowsEnglishAndSpanishOn' + family]))
    captures += ['harbor-server-note-' + language + '-' + family.lower() for language in ['en', 'es']]
batches.append(dict(id='ContinuePrivacyPendingIPhone', family='IPhone', seed=seed,
    cases=['HarborExistingAppUITests.ContinuePrivacyNavigationTests/testActualPrivateChoiceLocksSharedSourcesKeepsDownloadsEditableAndRestoresAllChoicesOnIPhone']))
captures += ['continue-private-' + state + '-iphone' for state in ['default', 'locked', 'restored', 'unlocked']]
captures += ['trakt-native-' + state + '-' + size for size in ['compact', 'regular'] for state in ['disconnected', 'connected', 'code', 'denied', 'card']]
for case in cases + [item for batch in batches for item in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(cases) == len(set(cases)) == 16 and len(captures) == len(set(captures)) == 18
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=16, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=3, expected_total_executions=22,
    expected_original_images=18, required_original_captures=captures, new_native_cases=10,
    affected_account_copy_asset_cases=affected, collect_launch_failure_diagnostics=True,
    original_reference='ios/HarborTests/Fixtures/trakt-scrobble-reference.json',
    provider_account_requests=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False,
    physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('10 new +6 genuinely affected native;3 fresh owned preparations +3 UI =22 executions/18 captures. No IPA.')

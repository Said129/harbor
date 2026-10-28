"""New Trakt library plus the two failed scrobble cases; keep every unaffected pass."""
import json
import os
from pathlib import Path
import re

block = 'trakt-library'
marker = 'affected:' + block
cases = []
for suite, count in [('TraktLibraryTests', 9), ('TraktLibraryMountTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
failed = [
    'HarborTests.TraktScrobbleTests/testExecutedDesktopResolutionsPreserveDirectHistoryFallbackMappedEpisodesAndSpecialMovies',
    'HarborTests.TraktScrobbleTests/testExecutedDesktopTargetsScrobbleBodiesAndHistoryReceiptsPreserveIDsAndExactDecimalRounding',
]
cases += failed
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
seed = 'HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource'
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='LibraryTrackerTabs' + family, family=family, seed=seed,
        cases=['HarborExistingAppUITests.LibraryTrackerTabsNavigationTests/testChangedLibraryTabsKeepLocalFiltersSelectableAndDisconnectedTrackersHiddenOn' + family]))
    captures += ['library-tracker-tabs-' + state + '-' + family.lower() for state in ['all', 'watchlist', 'continue']]
captures += ['trakt-library-native-' + state + '-' + size for size in ['compact', 'regular'] for state in ['watchlist', 'history', 'transfer']]
for case in cases + [item for batch in batches for item in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(cases) == len(set(cases)) == 12 and len(captures) == len(set(captures)) == 12
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=12, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=16,
    expected_original_images=12, required_original_captures=captures, new_native_cases=10,
    failed_scrobble_cases=failed, parent_run=40604874961, parent_source='e1367aeb8072860c05a87340ef285c26042a8411',
    collect_launch_failure_diagnostics=True,
    original_reference='ios/HarborTests/Fixtures/trakt-library-reference.json',
    provider_account_requests=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False,
    physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('10 new native +2 failed scrobble +2 fresh guests +2 affected tab UI=16 executions/12 originals; no IPA.')

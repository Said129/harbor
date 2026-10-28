"""New history contracts, the incomplete artwork capture and only the failed old phone route."""
import json
import os
from pathlib import Path
import re

block = 'library-history'
marker = 'affected:' + block
cases = []
for suite, count in [('LibraryHistoryTests', 6), ('LibraryHistoryMountTests', 1), ('TraktLibraryMountTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
seed = 'HarborTests.LibraryHistoryInterfaceSeedTests/testPrepareIndependentOwnedHistoryForTheRealLibraryInterface'
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='LibraryHistory' + family, family=family, seed=seed,
        cases=['HarborExistingAppUITests.LibraryHistoryNavigationTests/testIndependentHistorySwitchesModesSearchesConfirmsRemovalAndRestoresOn' + family]))
    captures += ['library-history-' + state + '-' + family.lower() for state in ['posters', 'episodes', 'removed']]
failed_phone = 'HarborExistingAppUITests.LibraryTrackerTabsNavigationTests/testChangedLibraryTabsKeepLocalFiltersSelectableAndDisconnectedTrackersHiddenOnIPhone'
batches.append(dict(id='LibraryTabsRepairIPhone', family='IPhone',
    seed='HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource', cases=[failed_phone]))
captures += ['library-tracker-tabs-' + state + '-iphone' for state in ['all', 'watchlist', 'continue']]
captures += ['library-history-native-' + mode + '-' + size for size in ['compact', 'regular'] for mode in ['posters', 'episodes']]
captures += ['trakt-library-native-' + state + '-' + size for size in ['compact', 'regular'] for state in ['watchlist', 'history', 'transfer']]
for case in cases + [item for batch in batches for item in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(cases) == len(set(cases)) == 8 and len(captures) == len(set(captures)) == 19
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=8, pending_native_cases=cases, new_native_cases=7,
    ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=3, expected_total_executions=14,
    expected_original_images=19, required_original_captures=captures,
    parent_run=40613602917, parent_source='a250493946884de12a2c269786996917ded08e42',
    failed_parent_ui=[failed_phone],
    genuinely_affected_native_cases=[cases[-1]],
    affected_mount_reason='The first compact original had one loading cover. The changed barrier requires all four actual owned covers before capture.',
    collect_launch_failure_diagnostics=True,
    original_reference='ios/HarborTests/Fixtures/library-history-reference.json',
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('7 new native +1 incomplete artwork mount +3 fresh preparations +2 new UI +1 failed phone UI=14 executions/19 originals; no IPA.')

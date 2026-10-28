"""Repair the unexecuted UI runner and only the two visually affected mounts."""
import json
import os
from pathlib import Path
import re

marker = 'affected:library-history-interface'
cases = []
for suite in ['LibraryHistoryMountTests', 'TraktLibraryMountTests']:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == 1
    cases += ['HarborTests.' + suite + '/' + methods[0]]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='LibraryHistory' + family, family=family,
        seed='HarborTests.LibraryHistoryInterfaceSeedTests/testPrepareIndependentOwnedHistoryForTheRealLibraryInterface',
        cases=['HarborExistingAppUITests.LibraryHistoryNavigationTests/testIndependentHistorySwitchesModesSearchesConfirmsRemovalAndRestoresOn' + family]))
    captures += ['library-history-' + state + '-' + family.lower() for state in ['posters', 'episodes', 'removed']]
batches.append(dict(id='LibraryTabsRepairIPhone', family='IPhone',
    seed='HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource',
    cases=['HarborExistingAppUITests.LibraryTrackerTabsNavigationTests/testChangedLibraryTabsKeepLocalFiltersSelectableAndDisconnectedTrackersHiddenOnIPhone']))
captures += ['library-tracker-tabs-' + state + '-iphone' for state in ['all', 'watchlist', 'continue']]
captures += ['library-history-native-' + mode + '-' + size for size in ['compact', 'regular'] for mode in ['posters', 'episodes']]
captures += ['trakt-library-native-' + state + '-' + size for size in ['compact', 'regular'] for state in ['watchlist', 'history', 'transfer']]
for case in cases + [item for batch in batches for item in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(captures) == len(set(captures)) == 19
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='library-history-interface', selection_marker=marker,
    selected_case_count=2, pending_native_cases=cases, new_native_cases=0, genuinely_affected_native_cases=cases,
    ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=3, expected_total_executions=8, expected_original_images=19, required_original_captures=captures,
    parent_run=40674798409, parent_source='079a5da425564110ffed6380f8aee889362b919b',
    parent_native_passes=9, parent_ui_executions=0, retained_unchanged_native_passes=7,
    collect_launch_failure_diagnostics=True, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Only2 changed mounts +3 unexecuted fresh preparations +3 unexecuted interfaces=8 executions/19 originals; other7 native passes retained.')

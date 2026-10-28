"""Only the two failed history search/removal journeys; all native and tab passes retained."""
import json
import os
from pathlib import Path
import re

marker = 'ui-only:history-search-interface'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='HistorySearch' + family, family=family,
        seed='HarborTests.LibraryHistoryInterfaceSeedTests/testPrepareIndependentOwnedHistoryForTheRealLibraryInterface',
        cases=['HarborExistingAppUITests.LibraryHistoryNavigationTests/testIndependentHistorySwitchesModesSearchesConfirmsRemovalAndRestoresOn' + family]))
    captures += ['library-history-' + state + '-' + family.lower() for state in ['posters', 'episodes', 'removed']]
for case in [case for batch in batches for case in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='history-search-interface', selection_marker=marker,
    selected_case_count=0, pending_native_cases=[], ui_only=True, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=4, expected_original_images=6, required_original_captures=captures,
    parent_run=40678694048, parent_source='8875df1dce5be6a2e289baa8bfedf9b93f036139',
    retained_native_passes=2, retained_phone_tabs_ui=True,
    collect_launch_failure_diagnostics=True, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Only2 failed history journeys +2 fresh preparations=4 executions/6 originals, no native or approved tab replay.')

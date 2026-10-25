"""Validate the new last-watcher merge and real phone/tablet continuation badges."""
import json
import os
from pathlib import Path
import re

marker = 'affected:watched-by'
cases = []
for suite, count in [('DesktopWatchedByTests', 3), ('WatchedBySyncTests', 7)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='WatchedBy' + family, family=family,
        seed='HarborTests.WatchedByInterfaceSeedTests/testPrepareAnotherOwnedWatcherAndAnExplicitDefaultOnAFreshGuest',
        cases=['HarborExistingAppUITests.PageContinuationNavigationTests/testOtherWatcherBadgeCoexistsWithAnimeCustomizationOn' + family]))
    captures += ['anime-continue-' + state + '-' + family.lower() for state in ['initial', 'editing', 'moved', 'renamed', 'hidden', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='watched-by', selection_marker=marker,
    selected_case_count=10, pending_native_cases=cases, ui_batches=batches, ui_cases=[batch['cases'][0] for batch in batches],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=14,
    expected_original_images=12, required_original_captures=captures,
    new_native_cases=10, retained_page_layout_native_run=40142488560, retained_page_layout_native_cases=20,
    retained_layout_batch_native_run=40156238216, retained_layout_batch_native_cases=6,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    household_account_activation_still_pending=True, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Watched by:10 new native+2fresh+2phone/tablet interfaces=14executions/12captures. No approved suites repeated, no IPA.')

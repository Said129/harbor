"""Run the unexecuted page layout contracts and new continuation routes only."""
import json
import os
from pathlib import Path
import re

marker = 'affected:anime-continue-layout'
cases = []
for suite, count in [('DesktopPageLayoutTests', 6), ('PageLayoutSyncTests', 10), ('AnimeContinuationLayoutTests', 4)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='AnimeContinuation' + family, family=family,
        seed='HarborTests.PageContinuationInterfaceSeedTests/testPrepareOwnedContinueHistoryAndPublicAnimeRowsOnAFreshGuest',
        cases=['HarborExistingAppUITests.PageContinuationNavigationTests/testAnimeContinueRowMovesRenamesHidesAndRestoresAfterRelaunchOn' + family]))
    captures += ['anime-continue-' + state + '-' + family.lower() for state in ['initial', 'editing', 'moved', 'renamed', 'hidden', 'restored']]
for case in [row['seed'] for row in batches] + [case for row in batches for case in row['cases']]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    folder = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + folder + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='anime-continue-layout', selection_marker=marker,
    selected_case_count=20, pending_native_cases=cases, ui_batches=batches, ui_cases=[row['cases'][0] for row in batches],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=24,
    expected_original_images=12, required_original_captures=captures,
    unexecuted_prior_native_cases=16, prior_page_layout_run=40140794453, prior_page_layout_actual_executions=0,
    new_native_cases=4, new_ui_cases=2, retained_anime_native_cases=8, retained_reader_native_cases=51,
    watched_by_adapter_still_pending=True, household_account_activation_still_pending=True,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    interface_review_pending=True, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Continue layout:16 unexecuted+4 new native,2 fresh,2 new UI=24 executions/12 captures. Approved suites retained; no IPA.')

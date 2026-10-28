"""Unexecuted list contracts/concurrency and only failed history interfaces after the compiler repair."""
import json
import os
from pathlib import Path
import re

marker = 'affected:custom-lists-repair'
cases = []
for suite, expected in [('CustomListTests', 4), ('CustomListConcurrencyTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == expected
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='CustomListsHistory' + family, family=family,
        seed='HarborTests.LibraryHistoryInterfaceSeedTests/testPrepareIndependentOwnedHistoryForTheRealLibraryInterface',
        cases=['HarborExistingAppUITests.LibraryHistoryNavigationTests/testIndependentHistorySwitchesModesSearchesConfirmsRemovalAndRestoresOn' + family]))
    captures += ['library-history-' + state + '-' + family.lower() for state in ['posters', 'episodes', 'removed']]
for case in cases + [case for batch in batches for case in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='custom-lists-repair', selection_marker=marker,
    selected_case_count=5, pending_native_cases=cases, new_native_cases=5,
    ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=9, expected_original_images=6, required_original_captures=captures,
    original_reference='ios/HarborTests/Fixtures/custom-lists-reference.json',
    compiler_parent_run=40682261066, compiler_parent_source='4c8e563a9c42feffb1d0cbfec72bf3b1e33b0a30',
    ui_parent_run=40678694048, ui_parent_source='8875df1dce5be6a2e289baa8bfedf9b93f036139',
    known_compiler_dependency_run=40684549235, native_custom_lists_interface_complete=False,
    collect_launch_failure_diagnostics=True, personal_account_requests_performed=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Five unexecuted list contracts +2 required fresh preparations +2 failed history interfaces=9 executions/6 originals; no approved replay or IPA.')

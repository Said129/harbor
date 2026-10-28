"""Only the five new manual mark cases; retain all approved tracker suites."""
import json
import os
from pathlib import Path
import re

marker = 'native-only:manual-watched'
suite = 'ManualWatchedSelectionTests'
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 5
cases = ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='manual-watched', selection_marker=marker,
    selected_case_count=5, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=5, expected_original_images=0, required_original_captures=[], new_native_cases=5,
    original_reference='ios/HarborTests/Fixtures/manual-mark-reference.json',
    retained_native_parent_run=40613602917, retained_native_parent_source='a250493946884de12a2c269786996917ded08e42',
    personal_account_requests_performed=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream:
        stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Five new manual mark executions, no repeated approved cases, interface claims or IPA.')

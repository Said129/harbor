"""Only the four new custom-list contract and owned persistence cases."""
import json
import os
from pathlib import Path
import re

marker = 'native-only:custom-lists-core'
suite = 'CustomListTests'
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 4
cases = ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='custom-lists-core', selection_marker=marker,
    selected_case_count=4, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=4, expected_original_images=0, required_original_captures=[], new_native_cases=4,
    original_reference='ios/HarborTests/Fixtures/custom-lists-reference.json',
    native_custom_lists_interface_complete=False, personal_account_requests_performed=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Four new custom-list contract/storage executions; no approved suite replay, interface approval or IPA.')

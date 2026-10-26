"""Select only the new Simkl library contracts and native rendered layouts."""
import json
import os
from pathlib import Path
import re

block = 'simkl-library'
marker = 'native-only:' + block
cases = []
for suite, count in [('SimklLibraryContractTests', 3), ('SimklLibrarySyncTests', 4), ('SimklLibraryPersistenceTests', 3), ('SimklLibraryMountTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
captures = ['simkl-library-native-' + state + '-' + layout for layout in ['compact', 'regular'] for state in ['movies', 'anime', 'actions']]
assert len(cases) == len(set(cases)) == 11
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=11, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=11, expected_original_images=6, required_original_captures=captures,
    library_reference='ios/HarborTests/Fixtures/simkl-library-reference.json',
    actual_native_layout_renders=True, actual_ipad_ui_journey_verified=False,
    synthetic_account_and_local_cover_pixels_only=True, personal_simkl_authorization_not_performed=True,
    approved_previous_cases_replayed=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('11new Simkl library cases,6native layout renders; no unrelated replay, real account mutation or IPA.')

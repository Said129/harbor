"""Only the new Book reader, its original pagination and actual mobile interaction."""
import json
import os
from pathlib import Path
import re

source = Path('ios/HarborTests/EBookPaginationTests.swift').read_text('utf-8').split('private struct BookPaginationNetwork:', 1)[0]
cases = ['HarborTests.EBookPaginationTests/' + method for method in re.findall(r'\bfunc (test\w+)\(', source)]
requested = [value.strip().replace('HarborTests/', 'HarborTests.', 1) for value in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(cases) == len(set(cases)) == len(requested) == 3 and set(requested) == set(cases)
seed = 'HarborTests.BookPaginationInterfaceSeedTests/testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest'
ui = ['HarborUITests.EBookPaginationNavigationTests/testActualBookPagesTurnsZoomAndReadingPositionRestoreOn' + device for device in ['IPhone', 'IPad']]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = 'EBookPaginationTests' if suite == 'BookPaginationInterfaceSeedTests' else suite
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
captures = ['book-pagination-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['continuous', 'book', 'turned', 'zoom', 'restored', 'continuous-resume']]
captures.append('book-pagination-spread-ipad')
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='book-pagination', selected_case_count=3,
    pending_native_cases=cases, new_native_cases=3, native_preparation_case=seed, ui_cases=ui,
    expected_total_executions=7, expected_original_images=13, required_original_captures=captures,
    original_layout_cases=9, original_resume_cases=4, original_paper_palettes=3,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('3 NEW Book contracts +2 fresh preparations +2 NEW phone/tablet routes,13 captures. No approved tests repeated and no IPA.')

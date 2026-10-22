"""Select only new book detail/list contracts and their fresh phone/tablet routes."""
import json
import os
from pathlib import Path
import re

cases = []
for suite in ['EBookDetailTests', 'EBookLibraryTests']:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    source = source.split('final class ' + suite + ': XCTestCase {', 1)[1]
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == len(set(methods)) == 3
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(requested) == len(set(requested)) == 6 and set(requested) == set(cases)
seed = 'HarborTests.EBookDetailInterfaceSeedTests/testPrepareOwnedBookVolumesInOneFreshGuestWithoutAnAccount'
ui = ['HarborUITests.EBookDetailNavigationTests/testOriginalBookVolumesSearchChapterReadingAndIndependentListsOn' + device for device in ['IPhone', 'IPad']]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + ('EBookDetailTests' if suite == 'EBookDetailInterfaceSeedTests' else suite) + '.swift').read_text('utf-8'))
captures = ['ebook-detail-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['volumes', 'chapters', 'chapter-search', 'reader', 'lists', 'favorites', 'read-later', 'bookmarks-removed']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='ebook-detail', selected_case_count=6,
    pending_native_cases=cases, new_native_cases=6, native_preparation_case=seed, ui_cases=ui,
    expected_total_executions=10, expected_original_images=16, required_original_captures=captures,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('6 new book detail/list models +2 fresh preparations +2 new UI routes. Retain all prior outcomes. No IPA.')

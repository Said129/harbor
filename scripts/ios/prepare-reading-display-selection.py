"""Select only new native font/display contracts and fresh actual reader interfaces."""
import json
import os
from pathlib import Path
import re

source = Path('ios/HarborTests/ReadingFontTests.swift').read_text('utf-8').split('final class ReadingFontTests: XCTestCase {', 1)[1]
cases = ['HarborTests.ReadingFontTests/' + method for method in re.findall(r'\bfunc (test\w+)\(', source)]
assert len(cases) == 2
requested = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(requested) == len(set(requested)) == 2 and set(requested) == set(cases)
seed = 'HarborTests.ReadingDisplayInterfaceSeedTests/testPrepareOwnedVolumeAndActualFontForNewReaderDisplayInterfaces'
ui = ['HarborUITests.ReadingDisplayNavigationTests/testActualReadingBrightnessAndImportedFontRestoreOn' + device for device in ['IPhone', 'IPad']]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = 'ReadingFontTests' if suite == 'ReadingDisplayInterfaceSeedTests' else suite
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
captures = ['reading-display-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['baseline', 'options', 'dim-reader', 'fonts', 'custom-reader', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-display', selected_case_count=2,
    pending_native_cases=cases, new_native_cases=2, native_preparation_case=seed, ui_cases=ui,
    expected_total_executions=6, expected_original_images=12, required_original_captures=captures,
    brightness_pixel_comparison_still_required=True, approved_predecessor_cases_repeated=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('2 NEW font contracts +2 fresh preparations +2 new actual reader UI routes. Keep approved cases. No IPA.')

"""Only the new raw web-font contracts and their actual mobile interfaces."""
import json
import os
from pathlib import Path
import re

source = Path('ios/HarborTests/ReadingWebFontTests.swift').read_text('utf-8').split('final class ReadingWebFontTests: XCTestCase {', 1)[1]
cases = ['HarborTests.ReadingWebFontTests/' + method for method in re.findall(r'\bfunc (test\w+)\(', source)]
assert len(cases) == 2
requested = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(requested) == len(set(requested)) == 2 and set(requested) == set(cases)
seed = 'HarborTests.ReadingWebFontInterfaceSeedTests/testPrepareBothOwnedWebFontsInTheOrdinaryFreshGuestReader'
groups = [[
    'HarborUITests.EBookDetailNavigationTests/testOriginalBookVolumesSearchChapterReadingAndIndependentListsOn' + device,
    'HarborUITests.ReadingDisplayNavigationTests/testActualReadingBrightnessAndImportedFontRestoreOn' + device,
    'HarborUITests.ReadingWebFontNavigationTests/testActualConvertedWebFontChoicesAndReaderOn' + device,
] for device in ['IPhone', 'IPad']]
ui = [case for group in groups for case in group]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = 'ReadingWebFontTests' if suite == 'ReadingWebFontInterfaceSeedTests' else suite
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
captures = ['web-font-' + state + '-' + format + '-' + device for device in ['iphone', 'ipad'] for format in ['woff', 'woff2'] for state in ['choices', 'reader']]
captures += ['ebook-detail-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['volumes', 'chapters', 'chapter-search', 'reader', 'lists', 'favorites', 'read-later', 'bookmarks-removed']]
captures += ['reading-display-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['baseline', 'options', 'dim-reader', 'fonts', 'custom-reader', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='web-fonts', selected_case_count=2,
    pending_native_cases=cases, new_native_cases=2, native_preparation_case=seed, ui_cases=ui, ui_device_cases=groups,
    expected_total_executions=10, expected_original_images=36, required_original_captures=captures,
    failed_ui_predecessor_runs=[39768078426, 39770691335], failed_ui_cases_retried=4,
    required_new_rust_cases=0, retained_rust_cases=5, retained_rust_run=39852325983, prior_ttf_otf_native_passes_retained=2,
    retained_production_cargo_check_run=39850934986,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('2 unexecuted web-font models +2 fresh preparations +6 unexecuted UI routes; retain5 approved Rust contracts and17 approved models. No IPA.')

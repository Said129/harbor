"""New chapter search/native brightness and the eight actually failed reader interfaces."""
import json
import os
from pathlib import Path
import re

cases = []
for suite in ['EBookSearchTests', 'ReadingBrightnessTests']:
    text = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    cases += ['HarborTests.' + suite + '/' + method for method in re.findall(r'\bfunc (test\w+)\(', text)]
requested = [value.strip().replace('HarborTests/', 'HarborTests.', 1) for value in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(cases) == len(set(cases)) == len(requested) == 3 and set(cases) == set(requested)
font_seed = 'HarborTests.ReadingWebFontInterfaceSeedTests/testPrepareBothOwnedWebFontsInTheOrdinaryFreshGuestReader'
book_seed = 'HarborTests.BookPaginationInterfaceSeedTests/testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest'
batches = []
for device in ['IPhone', 'IPad']:
    font_cases = [
        'HarborUITests.EBookDetailNavigationTests/testOriginalBookVolumesSearchChapterReadingAndIndependentListsOn' + device,
        'HarborUITests.ReadingDisplayNavigationTests/testActualReadingBrightnessAndImportedFontRestoreOn' + device,
        'HarborUITests.ReadingWebFontNavigationTests/testActualConvertedWebFontChoicesAndReaderOn' + device]
    book_cases = [
        'HarborUITests.EBookPaginationNavigationTests/testActualBookPagesTurnsZoomAndReadingPositionRestoreOn' + device,
        'HarborUITests.EBookSearchNavigationTests/testOriginalSealedChapterSearchJumpsInBothReadingModesOn' + device]
    batches += [dict(id=device, family=device, seed=font_seed, cases=font_cases), dict(id='Book' + device, family=device, seed=book_seed, cases=book_cases)]
ui = [case for batch in batches for case in batch['cases']]
assert len(ui) == len(set(ui)) == 10
for case in cases + [font_seed, book_seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = {'ReadingWebFontInterfaceSeedTests': 'ReadingWebFontTests', 'BookPaginationInterfaceSeedTests': 'EBookPaginationTests'}.get(suite, suite)
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
captures = ['web-font-' + state + '-' + format + '-' + device for device in ['iphone', 'ipad'] for format in ['woff', 'woff2'] for state in ['choices', 'reader']]
captures += ['ebook-detail-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['volumes', 'chapters', 'chapter-search', 'reader', 'lists', 'favorites', 'read-later', 'bookmarks-removed']]
captures += ['reading-display-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['baseline', 'options', 'dim-reader', 'fonts', 'custom-reader', 'restored']]
captures += ['book-pagination-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['continuous', 'book', 'turned', 'zoom', 'restored', 'continuous-resume']]
captures += ['book-pagination-spread-ipad']
captures += ['book-search-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['sealed', 'revealed', 'continuous-jump', 'resealed', 'book-jump', 'remembered']]
assert len(captures) == len(set(captures)) == 61
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-completion', selected_case_count=3,
    pending_native_cases=cases, new_native_cases=3, ui_cases=ui, ui_batches=batches,
    expected_total_executions=17, expected_original_images=61, required_original_captures=captures,
    new_ui_cases=2, failed_ui_cases_retried=8, fresh_preparation_executions=4,
    retained_native_model_cases=24, retained_rust_font_cases=5,
    retained_runs=[39763655130,39768078426,39770691335,39849464797,39856231737,39857311929,39852325983],
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('3 NEW models +4 fresh preparations +2 NEW and8 failed reader UI,61 captures. Retain24 Native models and5 Rust passes. No IPA.')

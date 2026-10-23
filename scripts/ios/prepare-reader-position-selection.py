"""Verify actual mounted paragraph restoration and retry only eight failed UI methods."""
import json
import os
from pathlib import Path
import re

suite = 'ReadingPositionMountTests'
cases = ['HarborTests.' + suite + '/' + method for method in re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))]
requested = [value.strip().replace('HarborTests/', 'HarborTests.', 1) for value in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(cases) == len(set(cases)) == len(requested) == 1 and set(cases) == set(requested)
font_seed = 'HarborTests.ReadingWebFontInterfaceSeedTests/testPrepareBothOwnedWebFontsInTheOrdinaryFreshGuestReader'
book_seed = 'HarborTests.BookPaginationInterfaceSeedTests/testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest'
batches, captures = [], []
routes = [
    ('Detail', 'EBookDetailNavigationTests/testOriginalBookVolumesSearchChapterReadingAndIndependentListsOn', font_seed,
        'ebook-detail', ['volumes', 'chapters', 'chapter-search', 'reader', 'lists', 'favorites', 'read-later', 'bookmarks-removed']),
    ('Display', 'ReadingDisplayNavigationTests/testActualReadingBrightnessAndImportedFontRestoreOn', font_seed,
        'reading-display', ['baseline', 'options', 'dim-reader', 'fonts', 'custom-reader', 'restored']),
    ('Font', 'ReadingWebFontNavigationTests/testActualConvertedWebFontChoicesAndReaderOn', font_seed, '', []),
    ('Book', 'EBookPaginationNavigationTests/testActualBookPagesTurnsZoomAndReadingPositionRestoreOn', book_seed,
        'book-pagination', ['continuous', 'book', 'turned', 'zoom', 'restored', 'continuous-resume']),
    ('Search', 'EBookSearchNavigationTests/testOriginalSealedChapterSearchJumpsInBothReadingModesOn', book_seed,
        'book-search', ['sealed', 'revealed', 'continuous-jump', 'resealed', 'book-jump', 'remembered'])]
for device in ['IPhone', 'IPad']:
    for label, method, seed, prefix, states in routes:
        if (device == 'IPad' and label == 'Detail') or (device == 'IPhone' and label == 'Book'): continue
        batches.append(dict(id=label + device, family=device, seed=seed, cases=['HarborUITests.' + method + device]))
        captures += [prefix + '-' + state + '-' + device.lower() for state in states]
        if label == 'Font': captures += ['web-font-' + state + '-' + format + '-' + device.lower() for format in ['woff', 'woff2'] for state in ['choices', 'reader']]
        if label == 'Book' and device == 'IPad': captures += ['book-pagination-spread-ipad']
ui = [case for batch in batches for case in batch['cases']]
assert len(batches) == len(ui) == len(set(ui)) == 8 and len(captures) == len(set(captures)) == 47
for case in cases + [font_seed, book_seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = {'ReadingWebFontInterfaceSeedTests': 'ReadingWebFontTests', 'BookPaginationInterfaceSeedTests': 'EBookPaginationTests'}.get(suite, suite)
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-position', selected_case_count=1,
    pending_native_cases=cases, new_native_cases=1, ui_cases=ui, ui_batches=batches,
    expected_total_executions=17, expected_original_images=47, required_original_captures=captures,
    failed_ui_cases_retried=8, fresh_preparation_executions=8, retained_native_model_cases=27, retained_rust_font_cases=5,
    retained_reader_ui_run=39877611403, retained_reader_ui_cases=[
        'HarborUITests.EBookDetailNavigationTests/testOriginalBookVolumesSearchChapterReadingAndIndependentListsOnIPad',
        'HarborUITests.EBookPaginationNavigationTests/testActualBookPagesTurnsZoomAndReadingPositionRestoreOnIPhone'],
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('1 NEW actual mounted scroll contract +8 fresh guests +8 failed UI,47 captures. Retain27 Native,5 Rust and2 passed reader UI. No IPA.')

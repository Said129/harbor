"""Only two unexecuted contents interfaces and the three remaining failed reader UI methods."""
import json
import os
from pathlib import Path
import re

marker = 'ui-only:reader-interface-completion'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
contents_seed = 'HarborTests.ReaderContentsInterfaceSeedTests/testPrepareOwnedVolumesAndSavedBookInOneFreshGuest'
book_seed = 'HarborTests.BookPaginationInterfaceSeedTests/testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest'
font_seed = 'HarborTests.ReadingWebFontInterfaceSeedTests/testPrepareBothOwnedWebFontsInTheOrdinaryFreshGuestReader'
batches, captures = [], []
for device in ['IPhone', 'IPad']:
    contents = 'HarborUITests.EBookReaderContentsNavigationTests/testOriginalReaderVolumePickerCurrentChapterAndRealChapterChangeOn' + device
    search = 'HarborUITests.EBookSearchNavigationTests/testOriginalSealedChapterSearchJumpsInBothReadingModesOn' + device
    batches += [dict(id='Contents' + device, family=device, seed=contents_seed, cases=[contents]), dict(id='Search' + device, family=device, seed=book_seed, cases=[search])]
    captures += ['reader-contents-' + state + '-' + device.lower() for state in ['current', 'volume', 'changed', 'next']]
    captures += ['book-search-' + state + '-' + device.lower() for state in ['sealed', 'revealed', 'continuous-jump', 'user-scroll', 'resealed', 'book-jump', 'remembered']]
batches += [dict(id='DisplayIPad', family='IPad', seed=font_seed, cases=['HarborUITests.ReadingDisplayNavigationTests/testActualReadingBrightnessAndImportedFontRestoreOnIPad'])]
captures += ['reading-display-' + state + '-ipad' for state in ['baseline', 'options', 'dim-reader', 'fonts', 'custom-reader', 'restored']]
ui = [case for batch in batches for case in batch['cases']]
assert len(batches) == len(ui) == len(set(ui)) == 5 and len(captures) == len(set(captures)) == 28
retained_ui = [
    'HarborUITests.EBookDetailNavigationTests/testOriginalBookVolumesSearchChapterReadingAndIndependentListsOn' + device for device in ['IPhone', 'IPad']]
retained_ui += ['HarborUITests.EBookPaginationNavigationTests/testActualBookPagesTurnsZoomAndReadingPositionRestoreOn' + device for device in ['IPhone', 'IPad']]
retained_ui += ['HarborUITests.ReadingWebFontNavigationTests/testActualConvertedWebFontChoicesAndReaderOn' + device for device in ['IPhone', 'IPad']]
retained_ui += ['HarborUITests.ReadingDisplayNavigationTests/testActualReadingBrightnessAndImportedFontRestoreOnIPhone']
assert len(retained_ui) == 7 and not set(ui).intersection(retained_ui)
for case in [contents_seed, book_seed, font_seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = {'ReadingWebFontInterfaceSeedTests': 'ReadingWebFontTests', 'BookPaginationInterfaceSeedTests': 'EBookPaginationTests'}.get(suite, suite)
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-interface-completion', selected_case_count=0,
    pending_native_cases=[], new_native_cases=0, ui_only=True, selection_marker=marker,
    ui_cases=ui, ui_batches=batches, fresh_preparation_executions=5,
    expected_total_executions=10, expected_original_images=28, required_original_captures=captures,
    new_unexecuted_ui_cases=2, failed_ui_cases_retried=3,
    retained_native_model_cases=28, retained_public_metadata_cases=1, retained_rust_font_cases=5,
    retained_reader_ui_cases=7, retained_reader_ui_methods=retained_ui, retained_runs=[39877611403,39883561558,39889589952,39881961134],
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('UI only:2 unexecuted contents+3 failed reader methods,5 fresh preparations,28 captures. Keep28 Native+1 public metadata+5 Rust and7 approved reader UI. No IPA.')

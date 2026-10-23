"""New notes plus only the actual failed search and translation interface methods."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.EBookAnnotationTests/'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
models = [marker + method for method in [
    'testActualJavaScriptCoreMatchesElevenOriginalReferenceRangeOverlapAndBatchCases',
    'testNativeSelectionMapsCrossParagraphUTF16RangesWithoutIncludingImageOrSeparatorCharacters',
    'testProtectedAnnotationFilesKeepBookProfileIdentityNewestOrderCapAndEditedCreationTime',
    'testRejectedAnnotationWriteKeepsThePreviousListAndAllowsRetryWithoutChangingTheNoteID',
    'testMountedNativeHighlightDrawsDensityAndRetainsImportedFontAttributesAndSourceText']]
note_seed = 'HarborTests.ReaderAnnotationInterfaceSeedTests/testPrepareOwnedChapterAndCrossChapterReferenceInOneFreshGuest'
search_seed = 'HarborTests.BookPaginationInterfaceSeedTests/testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest'
translation_seed = 'HarborTests.ReaderTranslationInterfaceSeedTests/testPrepareOwnedCachedTranslationsWithoutAnAPIKeyInOneFreshGuest'
batches, captures = [], []
for device in ['IPhone', 'IPad']:
    note = 'HarborUITests.EBookAnnotationNavigationTests/testOwnedNativeSelectionNoteStylingReferencesEditingAndDeletionOn' + device
    search = 'HarborUITests.EBookSearchNavigationTests/testOriginalSealedChapterSearchJumpsInBothReadingModesOn' + device
    translation = 'HarborUITests.EBookTranslationNavigationTests/testCachedChapterOriginalToggleAndProfileTranslationSettingsOn' + device
    batches += [dict(id='Notes' + device, family=device, seed=note_seed, cases=[note]), dict(id='Search' + device, family=device, seed=search_seed, cases=[search]), dict(id='Translation' + device, family=device, seed=translation_seed, cases=[translation])]
    captures += ['reader-notes-' + state + '-' + device.lower() for state in ['selection', 'editor', 'highlighted', 'reference', 'restored', 'deleted']]
    captures += ['book-search-' + state + '-' + device.lower() for state in ['sealed', 'revealed', 'continuous-jump', 'user-scroll', 'resealed', 'book-jump', 'remembered']]
    captures += ['reader-translation-' + state + '-' + device.lower() for state in ['cached', 'original', 'settings', 'choices', 'saved', 'restored']]
ui = [case for batch in batches for case in batch['cases']]
for case in models + [note_seed, search_seed, translation_seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = 'EBookPaginationTests' if suite == 'BookPaginationInterfaceSeedTests' else suite
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
assert len(batches) == len(set(ui)) == 6 and len(captures) == len(set(captures)) == 38
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-annotations', selected_case_count=5,
    pending_native_cases=models, new_native_cases=5, selection_marker=marker,
    ui_cases=ui, ui_batches=batches, fresh_preparation_executions=6, expected_total_executions=17,
    expected_original_images=38, required_original_captures=captures,
    new_unexecuted_ui_cases=2, failed_ui_cases_retried=4,
    retained_native_model_cases=35, retained_public_metadata_cases=1, retained_rust_font_cases=5,
    retained_translation_native_run=39938643487, retained_translation_native_cases=5,
    retained_translation_original_archive_sha256='a0c9d67f0d9da64d1ea484942b21938b88fa86efb481ab368f51f2c0fb17926a',
    retained_bookmark_run=39935330648, retained_bookmark_native_cases=2, retained_bookmark_ui_cases=2,
    retained_contents_ui_cases=2, retained_display_ui_case=1, retained_reader_ui_methods=12,
    previous_failed_search_run=39933605950, previous_failed_translation_ui_run=39938643487,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in models) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('5NEW note contracts+6fresh+2NEW notes UI+4actual failed reader UI=17cases38captures. Keep35 Native+1public+5Rust and12readerUI; do not repeat passed methods. No IPA.')

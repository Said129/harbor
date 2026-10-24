"""Only failed or affected unexecuted reader/catalog routes, without native model replay."""
import json
import os
from pathlib import Path
import re

marker = 'ui-only:reading-final-repair'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
batches, captures = [], []
metadata_seed = 'EBookMetadataInterfaceSeedTests/testPrepareReadingSourcesAndOriginalPublicBookCacheOnAFreshGuest'
bookmark_seed = 'ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest'

def add(label, family, seed, case, names):
    batches.append(dict(id=label + family, family=family, seed='HarborTests.' + seed, cases=['HarborUITests.' + case + family]))
    captures.extend(name + '-' + family.lower() for name in names)

add('Catalog', 'IPhone', metadata_seed, 'HarborReadingCompletionNavigationTests/testBookCatalogOn',
    ['ebook-catalog-' + state for state in ['grouped', 'detail', 'alternate-reader', 'filters', 'manga-tag']])
for family in ['IPhone', 'IPad']:
    add('Metadata', family, metadata_seed, 'HarborReadingCompletionNavigationTests/testBookMetadataOn',
        ['ebook-metadata-' + state for state in ['discover', 'detail', 'reader', 'search', 'settings', 'cache-cleared']])
add('HTML', 'IPad', metadata_seed, 'HarborReadingHTMLNavigationTests/testManualSourceEditorValidationAndActualMangaAndBookReadersOn',
    ['reading-html-' + state for state in ['editor', 'saved', 'invalid', 'manga-reader', 'book-catalog', 'book-reader']])
add('Heading', 'IPhone', 'ReaderHeadingInterfaceSeedTests/testPrepareOwnedEmbeddedCoverEPUBInOneFreshGuest',
    'EBookReaderHeadingNavigationTests/testEmbeddedCoverAndChapterHeadingKeepTheRealChapterWhenReopeningAndRotatingOn',
    ['reader-heading-' + state for state in ['cover', 'first', 'second', 'light', 'restored']])
for family in ['IPhone', 'IPad']:
    add('Focus', family, bookmark_seed, 'EBookReaderChromeNavigationTests/testFocusHidesAndRevealsControlsKeepsPanelsUsableAndRestoresAfterRelaunchOn',
        ['reader-focus-' + state for state in ['initial', 'panel', 'hidden', 'revealed', 'restored', 'disabled']])
add('Narration', 'IPad', bookmark_seed, 'EBookNarrationNavigationTests/testVoiceSearchSelectionRestorationAndRotatedPanelOn',
    ['reader-narration-' + state for state in ['voices', 'search', 'selected', 'restored', 'rotated']])
add('NarrationRotation', 'IPhone', bookmark_seed, 'EBookNarrationNavigationTests/testUnselectedVoiceCanBeRevealedAndChosenInsideTheLandscapeViewportOn',
    ['reader-voice-landscape-before', 'reader-voice-landscape-after'])
add('Search', 'IPad', 'BookPaginationInterfaceSeedTests/testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest',
    'EBookSearchNavigationTests/testOriginalSealedChapterSearchJumpsInBothReadingModesOn',
    ['book-search-' + state for state in ['sealed', 'revealed', 'continuous-jump', 'user-scroll', 'resealed', 'book-jump', 'remembered']])
ui = [case for batch in batches for case in batch['cases']]
for case in [row['seed'] for row in batches] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = 'EBookPaginationTests' if suite == 'BookPaginationInterfaceSeedTests' else suite
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
assert len(set(ui)) == len(batches) == 10 and len(set(captures)) == 54
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-final-repair', selection_marker=marker,
    selected_case_count=0, pending_native_cases=[], ui_only=True, ui_batches=batches, ui_cases=ui,
    fresh_preparation_executions=10, expected_total_executions=20, expected_original_images=54,
    required_original_captures=captures, retained_native_model_cases=51,
    retained_public_metadata_cases=1, retained_rust_font_cases=5,
    latest_reader_run=40040069084, previous_source_run=40033688583,
    failed_ui_cases_retried=8, latest_run_unexecuted_ui_cases=3, new_ui_cases=1, new_ui_methods=[ui[-2]],
    approved_predecessor_cases_repeated=True, approved_predecessor_repeated_count=1,
    only_changed_approved_cases_repeated=[ui[-1]],
    changed_approved_reasons=['iPad search destination geometry changed with the continuous article; run 40040069084 timed out before this route executed'],
    passed_latest_reader_cases_repeated=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('UI only:8 failed +1 affected unexecuted route +1 new landscape selection +10 fresh=20cases54captures; native51 and latest passed reader cases retained. No IPA.')

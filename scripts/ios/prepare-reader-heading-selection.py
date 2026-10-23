"""New reader presentation plus two failed and two changed interface journeys; no native replay."""
import json
import os
from pathlib import Path
import re

marker = 'ui-only:reader-heading'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
batches, captures, affected = [], [], []
for family in ['IPhone', 'IPad']:
    heading = 'HarborUITests.EBookReaderHeadingNavigationTests/testEmbeddedCoverAndChapterHeadingKeepTheRealChapterWhenReopeningAndRotatingOn' + family
    search = 'HarborUITests.EBookSearchNavigationTests/testOriginalSealedChapterSearchJumpsInBothReadingModesOn' + family
    voice = 'HarborUITests.EBookNarrationNavigationTests/testVoiceSearchSelectionRestorationAndRotatedPanelOn' + family
    for label, seed, case in [
        ('Heading', 'ReaderHeadingInterfaceSeedTests/testPrepareOwnedEmbeddedCoverEPUBInOneFreshGuest', heading),
        ('Search', 'BookPaginationInterfaceSeedTests/testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest', search),
        ('Narration', 'ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest', voice)]:
        batches.append(dict(id=label + family, family=family, seed='HarborTests.' + seed, cases=[case]))
    batches.append(dict(id='Focus' + family, family=family,
        seed='HarborTests.ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest',
        cases=['HarborUITests.EBookReaderChromeNavigationTests/testFocusHidesAndRevealsControlsKeepsPanelsUsableAndRestoresAfterRelaunchOn' + family]))
    if family == 'IPhone': affected.append(voice)
    else: affected.append(search)
    captures += ['reader-heading-' + state + '-' + family.lower() for state in ['cover', 'first', 'second', 'light', 'restored']]
    captures += ['book-search-' + state + '-' + family.lower() for state in ['sealed', 'revealed', 'continuous-jump', 'user-scroll', 'resealed', 'book-jump', 'remembered']]
    captures += ['reader-narration-' + state + '-' + family.lower() for state in ['voices', 'search', 'selected', 'restored', 'rotated']]
    captures += ['reader-focus-' + state + '-' + family.lower() for state in ['initial', 'panel', 'hidden', 'revealed', 'restored', 'disabled']]
ui = [case for batch in batches for case in batch['cases']]
for case in [row['seed'] for row in batches] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = 'EBookPaginationTests' if suite == 'BookPaginationInterfaceSeedTests' else suite
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
assert len(set(ui)) == len(batches) == 8 and len(set(captures)) == 46 and len(affected) == 2
assert not any('Annotation' in case for case in ui)
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-heading', selection_marker=marker,
    selected_case_count=0, pending_native_cases=[], ui_only=True,
    new_ui_cases=2, failed_ui_cases_retried=4, changed_ui_cases_retried=2,
    ui_batches=batches, ui_cases=ui, fresh_preparation_executions=8,
    expected_total_executions=16, expected_original_images=46, required_original_captures=captures,
    retained_native_model_cases=51, retained_public_metadata_cases=1, retained_rust_font_cases=5,
    retained_reader_ui_methods=18, previous_reader_run=40031322009,
    approved_predecessor_cases_repeated=True, approved_predecessor_repeated_count=2,
    only_changed_approved_cases_repeated=affected,
    changed_approved_reasons=['Voice selection and landscape keyboard dismissal change the phone panel presentation',
        'The continuous article and heading change the pad search destination geometry'],
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('UI only:2 NEW heading +4 failed +2 changed routes +8 fresh=16cases46captures; no approved native suites or IPA.')

"""Keep actual passes; retry live Edge and six failed UI routes with two new token/lifetime contracts."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.EBookEdgeTokenTests/'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
models = [marker + name for name in [
    'testActualJavaScriptCoreMatches129IndependentV2TokensAndNativeRequestKeepsThePublicClientToken',
    'testNarratorObserverLifetimeReleasesTheOwnerWithoutCrossingActorIsolation']]
models += ['HarborTests.EBookNarrationTests/testLiveEdgeCatalogAndGeneratedMP3UseTheActualNativeWebSocket',
    'HarborTests.EBookAnnotationTests/testMountedNativeHighlightDrawsDensityAndRetainsImportedFontAttributesAndSourceText']
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    for label, seed, suite, method in [
        ('Notes', 'ReaderAnnotationInterfaceSeedTests/testPrepareOwnedChapterAndCrossChapterReferenceInOneFreshGuest', 'EBookAnnotationNavigationTests', 'testOwnedNativeSelectionNoteStylingReferencesEditingAndDeletionOn'),
        ('Search', 'BookPaginationInterfaceSeedTests/testPrepareOwnedPaginatedBookInTheOrdinaryFreshGuest', 'EBookSearchNavigationTests', 'testOriginalSealedChapterSearchJumpsInBothReadingModesOn'),
        ('Narration', 'ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest', 'EBookNarrationNavigationTests', 'testVoiceSearchSelectionRestorationAndRotatedPanelOn')]:
        batches.append(dict(id=label + family, family=family, seed='HarborTests.' + seed, cases=['HarborUITests.' + suite + '/' + method + family]))
    captures += ['reader-notes-' + state + '-' + family.lower() for state in ['selection', 'editor', 'highlighted', 'reference', 'restored', 'deleted']]
    captures += ['book-search-' + state + '-' + family.lower() for state in ['sealed', 'revealed', 'continuous-jump', 'user-scroll', 'resealed', 'book-jump', 'remembered']]
    captures += ['reader-narration-' + state + '-' + family.lower() for state in ['voices', 'search', 'selected', 'restored', 'rotated']]
ui = [case for batch in batches for case in batch['cases']]
for case in models + [row['seed'] for row in batches] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    file = 'EBookPaginationTests' if suite == 'BookPaginationInterfaceSeedTests' else suite
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + file + '.swift').read_text('utf-8'))
assert len(set(models)) == 4 and len(set(ui)) == len(batches) == 6 and len(set(captures)) == 36
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-narration-repair', selection_marker=marker,
    selected_case_count=4, pending_native_cases=models, new_native_cases=2, failed_native_cases_retried=1,
    changed_appearance_setup_cases_retried=1, ui_batches=batches, ui_cases=ui, fresh_preparation_executions=6,
    expected_total_executions=16, expected_original_images=36, required_original_captures=captures,
    retained_native_model_cases=45, retained_public_metadata_cases=1, retained_rust_font_cases=5, retained_reader_ui_methods=14,
    retained_narration_model_run=39951962364, retained_narration_original_archive_sha256='de3b502640431febe231c5df395cbf733dfd74c50fcac5d933c3437f40641d03',
    retained_translation_ui_cases=2, previous_failed_reader_run=39951962364,
    approved_predecessor_cases_repeated=True, approved_predecessor_repeated_count=1, only_changed_approved_case_repeated=models[-1],
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, native_live_edge_cases=1,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in models) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('2 NEW +1 live Edge retry +1 changed appearance setup +6 fresh +6 failed UI=16cases36captures. Preserve45 native+14readerUI; no unrelated replay or IPA.')

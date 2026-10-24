"""Retry exactly six authenticated failures; retain all four newly passed reader journeys."""
import json
import os
from pathlib import Path
import re

marker = 'ui-only:reading-final-followup'
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
for family in ['IPhone', 'IPad']:
    add('Focus', family, bookmark_seed, 'EBookReaderChromeNavigationTests/testFocusHidesAndRevealsControlsKeepsPanelsUsableAndRestoresAfterRelaunchOn',
        ['reader-focus-' + state for state in ['initial', 'panel', 'hidden', 'revealed', 'restored', 'disabled']])
add('Narration', 'IPad', bookmark_seed, 'EBookNarrationNavigationTests/testVoiceSearchSelectionRestorationAndRotatedPanelOn',
    ['reader-narration-' + state for state in ['voices', 'search', 'selected', 'restored', 'rotated']])
ui = [case for batch in batches for case in batch['cases']]
for case in [row['seed'] for row in batches] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
assert len(set(ui)) == len(batches) == 6 and len(set(captures)) == 34
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-final-followup', selection_marker=marker,
    selected_case_count=0, pending_native_cases=[], ui_only=True, ui_batches=batches, ui_cases=ui,
    fresh_preparation_executions=6, expected_total_executions=12, expected_original_images=34,
    required_original_captures=captures, retained_native_model_cases=51,
    retained_public_metadata_cases=1, retained_rust_font_cases=5,
    latest_reader_run=40051396481, latest_run_actual_executions=20, latest_run_actual_passed=14,
    failed_ui_cases_retried=6, new_ui_cases=0, cold_cache_preparation_checked=True,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('UI only:6 authenticated failed routes+6 fresh preparations=12 executions/34 captures;51 native and four newly passed reader routes retained. No IPA.')

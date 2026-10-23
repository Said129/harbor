"""Exercise the fresh-source race and only six previously failed catalogue/source routes."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.EBookSourceRefreshTests/'
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested in (marker, 'native-only:' + marker)
models = [marker + 'testFreshProviderSearchReplacesTheEnrichedAliasAndPublishesBeforeTheSlowCatalogFinishes']
seed = 'HarborTests.EBookMetadataInterfaceSeedTests/testPrepareReadingSourcesAndOriginalPublicBookCacheOnAFreshGuest'
routes = [
    ('Catalog', 'IPhone', 'HarborReadingCompletionNavigationTests', 'testBookCatalogOn', 'ebook-catalog', ['grouped', 'detail', 'alternate-reader', 'filters', 'manga-tag']),
    ('Metadata', 'IPhone', 'HarborReadingCompletionNavigationTests', 'testBookMetadataOn', 'ebook-metadata', ['discover', 'detail', 'reader', 'search', 'settings', 'cache-cleared']),
    ('Sources', 'IPhone', 'HarborReadingCompletionNavigationTests', 'testReadingSourcesOn', 'reading-plugin', ['manga-installed', 'manga-repository', 'books-installed', 'manga-search', 'manga-reader', 'book-search', 'book-reader', 'book-next']),
    ('Metadata', 'IPad', 'HarborReadingCompletionNavigationTests', 'testBookMetadataOn', 'ebook-metadata', ['discover', 'detail', 'reader', 'search', 'settings', 'cache-cleared']),
    ('Sources', 'IPad', 'HarborReadingCompletionNavigationTests', 'testReadingSourcesOn', 'reading-plugin', ['manga-installed', 'manga-repository', 'books-installed', 'manga-search', 'manga-reader', 'book-search', 'book-reader', 'book-next']),
    ('HTML', 'IPad', 'HarborReadingHTMLNavigationTests', 'testManualSourceEditorValidationAndActualMangaAndBookReadersOn', 'reading-html', ['editor', 'saved', 'invalid', 'manga-reader', 'book-catalog', 'book-reader'])]
batches, captures = [], []
for label, family, suite, method, prefix, states in routes:
    batches.append(dict(id=label + family, family=family, seed=seed, cases=['HarborUITests.' + suite + '/' + method + family]))
    captures += [prefix + '-' + state + '-' + family.lower() for state in states]
ui = [case for batch in batches for case in batch['cases']]
for case in models + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
assert len(set(models)) == 1 and len(set(ui)) == len(batches) == 6 and len(set(captures)) == 39
assert not any(value in case for case in ui for value in ['testBookCatalogOnIPad', 'testReadingBulkOn', 'ReadersOnIPhone'])
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-source-refresh', selection_marker=marker,
    selected_case_count=1, pending_native_cases=models, new_native_cases=1,
    ui_batches=batches, ui_cases=ui, fresh_preparation_executions=6, failed_ui_cases_retried=6,
    previous_failed_reading_run=39881961134, expected_total_executions=13,
    expected_original_images=39, required_original_captures=captures,
    retained_native_model_cases=45, retained_public_metadata_cases=1, retained_rust_font_cases=5,
    retained_reader_ui_methods=14, approved_predecessor_cases_repeated=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
native_only = requested.startswith('native-only:')
if native_only:
    plan.update(block='source-refresh-probe', selection_marker=requested, new_native_cases=0, failed_native_cases_retried=1,
        ui_batches=[], ui_cases=[], fresh_preparation_executions=0, failed_ui_cases_retried=0,
        previous_failed_native_run=40033688583, retained_native_model_cases=48, expected_total_executions=1,
        expected_original_images=0, required_original_captures=[])
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in models) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=' + ('false' if native_only else 'true') + '\n')
print('1 actual FAILED native fresh-source race retry only; keep both existing UI runs; no IPA.' if native_only else '1 NEW native fresh-source race +6 fresh guests +6 failed UI=13cases39captures. Retain approved routes; no IPA.')

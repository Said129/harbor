"""A real public metadata contract and only failed or unexecuted reading UI routes."""
import json
import os
from pathlib import Path
import re

cases = ['HarborIntegrationTests.EBookMetadataPublicTests/testActualPublicMetadataSearchReturnsTheNamedBookAndAuthorWithoutAnAccountOrAPIKey']
requested = [value.strip().replace('HarborIntegrationTests/', 'HarborIntegrationTests.', 1) for value in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert requested == cases
seed = 'HarborTests.EBookMetadataInterfaceSeedTests/testPrepareReadingSourcesAndOriginalPublicBookCacheOnAFreshGuest'
batches, captures = [], []
routes = [
    ('Catalog', 'testBookCatalogOn', 'ebook-catalog', ['grouped', 'detail', 'alternate-reader', 'filters', 'manga-tag']),
    ('Metadata', 'testBookMetadataOn', 'ebook-metadata', ['discover', 'detail', 'reader', 'search', 'settings', 'cache-cleared']),
    ('Sources', 'testReadingSourcesOn', 'reading-plugin', ['manga-installed', 'manga-repository', 'books-installed', 'manga-search', 'manga-reader', 'book-search', 'book-reader', 'book-next']),
    ('HTML', 'testManualSourceEditorValidationAndActualMangaAndBookReadersOn', 'reading-html', ['editor', 'saved', 'invalid', 'manga-reader', 'book-catalog', 'book-reader']),
    ('Bulk', 'testReadingBulkOn', 'reading-bulk', ['before', 'progress', 'partial', 'uninstalled'])]
for device in ['IPhone', 'IPad']:
    for label, method, prefix, states in routes:
        # The original phone bulk UI already passed. Preserve that outcome.
        if device == 'IPhone' and label == 'Bulk': continue
        suite = 'HarborReadingHTMLNavigationTests' if label == 'HTML' else 'HarborReadingCompletionNavigationTests'
        case = 'HarborUITests.' + suite + '/' + method + device
        batches.append(dict(id=label + device, family=device, seed=seed, cases=[case]))
        captures += [prefix + '-' + state + '-' + device.lower() for state in states]
ui = [case for batch in batches for case in batch['cases']]
assert len(ui) == len(set(ui)) == len(batches) == 9
assert len(captures) == len(set(captures)) == 54
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-surface', selected_case_count=1,
    pending_native_cases=cases, native_scheme='HarborLive', new_live_integration_cases=1,
    ui_cases=ui, ui_batches=batches, fresh_preparation_executions=9,
    expected_total_executions=19, expected_original_images=54, required_original_captures=captures,
    failed_ui_cases_retried=4, previously_unexecuted_ui_cases=5,
    retained_native_model_cases=27, retained_rust_font_cases=5, retained_phone_bulk_ui_run=39849464797,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('1 NEW actual public metadata integration +9 fresh preparations +4 failed/5 pending UI,54 captures. Keep27 Native models,5 Rust and the passed phone bulk UI. No IPA.')

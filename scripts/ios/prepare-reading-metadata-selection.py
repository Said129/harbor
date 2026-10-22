"""Select new book metadata, unexecuted HTML and the one actual catalog failure."""
import json
import os
from pathlib import Path
import re

cases = []
for suite, count in [('EBookMetadataTests', 6)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
failed = 'HarborTests.EBookCatalogTests/testRealReadingWorkerCoalescesSupportedTagsAndSeparatesOriginalFromContentLanguage'
cases.append(failed)
requested = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(cases) == len(requested) == len(set(requested)) == 7 and set(cases) == set(requested)
seed = 'HarborTests.EBookMetadataInterfaceSeedTests/testPrepareReadingSourcesAndOriginalPublicBookCacheOnAFreshGuest'
groups, captures = [], []
for device, label in [('IPhone', 'iphone'), ('IPad', 'ipad')]:
    groups.append(['HarborUITests.HarborReadingCompletionNavigationTests/test' + route + 'On' + device for route in ['ReadingSources', 'BookCatalog', 'ReadingBulk', 'BookMetadata']]
        + ['HarborUITests.HarborReadingHTMLNavigationTests/testManualSourceEditorValidationAndActualMangaAndBookReadersOn' + device])
    for prefix, states in [
        ('reading-plugin', ['manga-installed', 'manga-repository', 'books-installed', 'manga-search', 'manga-reader', 'book-search', 'book-reader', 'book-next']),
        ('ebook-catalog', ['grouped', 'detail', 'alternate-reader', 'filters', 'manga-tag']),
        ('reading-bulk', ['before', 'progress', 'partial', 'uninstalled']),
        ('ebook-metadata', ['discover', 'detail', 'reader', 'search', 'settings', 'cache-cleared']),
        ('reading-html', ['editor', 'saved', 'invalid', 'manga-reader', 'book-catalog', 'book-reader'])]:
        captures += [prefix + '-' + state + '-' + label for state in states]
ui = [case for group in groups for case in group]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
assert len(captures) == len(set(captures)) == 58
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-metadata', selected_case_count=7,
    pending_native_cases=cases, new_native_cases=6, failed_native_cases=[failed], html_models_retained_in_existing_run=39676396973,
    native_preparation_case=seed, ui_cases=ui, ui_device_cases=groups, expected_total_executions=19,
    expected_original_images=58, required_original_captures=captures, independent_interface_cases=True,
    prior_actual_native_passes_retained=12, predecessor_run=39672288309,
    approved_predecessor_cases_repeated=False, prior_preparation_repeated_only_for_fresh_devices=True,
    unrelated_approved_cases_selected=False, new_rust_cases=2, affected_rust_guard_cases=1,
    full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('7 new/failed models, 2 fresh preparations and 10 affected independent UI routes. 58 captures. Existing HTML models stay in their original run. No IPA.')

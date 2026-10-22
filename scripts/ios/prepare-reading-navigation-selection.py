"""Verify the two new repository contracts and retry only ten failed reading UI routes."""
import json
import os
from pathlib import Path
import re

cases = ['HarborTests.ReadingRoutingTests/' + method for method in re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/ReadingRoutingTests.swift').read_text('utf-8'))]
requested = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(cases) == len(set(cases)) == len(requested) == 2 and set(cases) == set(requested)
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
seed = 'HarborTests.EBookMetadataInterfaceSeedTests/testPrepareReadingSourcesAndOriginalPublicBookCacheOnAFreshGuest'
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
assert len(ui) == 10 and len(captures) == 58
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-navigation', selected_case_count=2,
    pending_native_cases=cases, new_native_cases=2, expected_total_executions=14,
    native_preparation_case=seed, ui_cases=ui, ui_device_cases=groups, expected_original_images=58, required_original_captures=captures,
    predecessor_run=39763655130, retained_native_passes=17, retained_rust_passes=3,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('2 new repository contracts, 2 necessary fresh preparations, 10 failed UI routes only; keep all 17 approved models. No IPA.')

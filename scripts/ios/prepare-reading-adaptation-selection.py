"""Select failed metadata plus new cross-room adaptation and local EPUB contracts."""
import json
import os
from pathlib import Path
import re

cases = []
for suite, count in [('EBookAdaptationTests', 3), ('EBookLocalMetadataTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
failed = ['HarborTests.EBookMetadataTests/' + method for method in re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/EBookMetadataTests.swift').read_text('utf-8')) if method != 'testCacheRejectsAnotherOwnerAndDiscardsKeysOutsideOriginalPublicCacheNamespaces']
assert len(failed) == 5
cases += failed
requested = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in os.environ['HARBOR_NATIVE_SELECTION'].split(',')]
assert len(requested) == len(set(requested)) == 9 and set(requested) == set(cases)
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
assert len(captures) == 58
ui = [case for group in groups for case in group]
seed = 'HarborTests.EBookMetadataInterfaceSeedTests/testPrepareReadingSourcesAndOriginalPublicBookCacheOnAFreshGuest'
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-adaptations', selected_case_count=9,
    pending_native_cases=cases, new_native_cases=4, failed_native_cases=failed, expected_total_executions=21,
    native_preparation_case=seed, ui_cases=ui, ui_device_cases=groups, expected_original_images=58, required_original_captures=captures,
    predecessor_run=39757601970, retained_native_passes=2, retained_rust_passes=3,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False,
    adaptation_interface_validation_still_required=True, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('5 failed metadata + 4 new adaptation/local EPUB models, 2 fresh preparations and 10 unexecuted UI routes. Retain 2 native/3 Rust passes. No IPA.')

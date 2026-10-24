"""Select only new original Billboard contracts and two new mobile journeys."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.MusicBillboardNativeTests/'
cases = []
for suite, count in [('MusicBillboardNativeTests', 4), ('MusicBillboardModelTests', 1), ('MusicBillboardPublicTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='Billboard' + family, family=family,
        seed='HarborTests.MusicExploreInterfaceSeedTests/testPrepareAnUnconfiguredGuestWithOriginalExploreFilters',
        cases=['HarborUITests.MusicBillboardNavigationTests/testPublicRanksAlbumChartLocalSearchCountrySelectionAndReturnToGenresOn' + family]))
    captures += ['music-billboard-' + state + '-' + family.lower() for state in ['ranks', 'detail', 'albums', 'search', 'country', 'genres']]
for case in cases + [row['seed'] for row in batches] + [row['cases'][0] for row in batches]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
assert len(cases) == 6 and len(set(captures)) == 12
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-billboard', selection_marker=marker,
    selected_case_count=6, pending_native_cases=cases, ui_batches=batches, ui_cases=[row['cases'][0] for row in batches],
    fresh_preparation_executions=2, expected_total_executions=10, expected_original_images=12, required_original_captures=captures,
    new_native_cases=6, new_ui_cases=2, failed_ui_cases_retried=0,
    retained_music_catalog_native_cases=6, retained_music_collection_native_cases=3,
    retained_music_rust_run=40054397288, retained_music_rust_cases=41, existing_rust_tests_repeated=False,
    retained_reader_native_cases=51, unrelated_approved_cases_selected=False,
    full_billboard_parity_complete=False, full_music_parity_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Billboard:6 NEW native+2fresh+2new UI=10 executions/12 original captures; unrelated reader/Music/Rust passes retained. No IPA.')

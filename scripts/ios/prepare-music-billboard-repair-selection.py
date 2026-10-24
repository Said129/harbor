"""Retry four failed Billboard cases, one affected resolver and the two unfinished UI journeys."""
import json
import os
from pathlib import Path
import re

marker = 'affected:music-billboard'
cases = []
for suite in ['MusicBillboardNativeTests', 'MusicBillboardPublicTests']:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
assert len(cases) == 5 and len(set(cases)) == 5
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker or os.environ['HARBOR_NATIVE_SELECTION'].strip().split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='Billboard' + family, family=family,
        seed='HarborTests.MusicExploreInterfaceSeedTests/testPrepareAnUnconfiguredGuestWithOriginalExploreFilters',
        cases=['HarborUITests.MusicBillboardNavigationTests/testPublicRanksAlbumChartLocalSearchCountrySelectionAndReturnToGenresOn' + family]))
    captures += ['music-billboard-' + state + '-' + family.lower() for state in ['ranks', 'detail', 'albums', 'search', 'country', 'genres']]
affected = 'HarborTests.MusicBillboardNativeTests/testOriginalAlbumResolverRequiresExactlyOneMatchingTitleAndArtist'
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-billboard-repair', selection_marker=marker,
    selected_case_count=5, pending_native_cases=cases, ui_batches=batches, ui_cases=[row['cases'][0] for row in batches],
    fresh_preparation_executions=2, expected_total_executions=9, expected_original_images=12, required_original_captures=captures,
    new_native_cases=0, new_ui_cases=0, failed_native_cases_retried=4, failed_ui_cases_retried=2,
    changed_approved_native_cases=[affected], changed_contract='Billboard original parsing and resolution move from a DOM-less worker to the pinned document host',
    latest_music_run=40089461727, retained_billboard_model_cases=1,
    retained_explore_native_cases=5, retained_public_catalog_phone_ui_case=1,
    retained_music_rust_run=40054397288, retained_music_rust_cases=41, existing_rust_tests_repeated=False,
    retained_reader_native_cases=51, unrelated_approved_cases_selected=False,
    full_billboard_parity_complete=False, full_music_parity_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Billboard repair:4failed+1affected native,2fresh+2failed UI=9 executions/12 captures. Untouched model and other native passes retained. No IPA.')

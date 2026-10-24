"""Exercise the original artist metadata modules, native lifecycle and new phone/tablet interfaces only."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.MusicArtistNativeTests/'
cases = []
for suite, count in [('MusicArtistNativeTests', 6), ('MusicArtistModelTests', 2)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
cases += ['HarborTests.MusicBillboardModelTests/testEmptySearchShowsEveryPublishedRankBeforeFilteringAndAfterClearingSearch']
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='Artists' + family, family=family,
        seed='HarborTests.MusicExploreInterfaceSeedTests/testPrepareAnUnconfiguredGuestWithOriginalExploreFilters',
        cases=['HarborUITests.MusicArtistNavigationTests/testPublicGenreArtistsProviderCreditsAndPrivateMetadataSettingsOn' + family]))
    captures += ['music-artists-' + state + '-' + family.lower() for state in ['credits', 'credit-artist', 'roster', 'roster-detail', 'settings', 'settings-removed']]
    batches.append(dict(id='Billboard' + family, family=family,
        seed='HarborTests.MusicExploreInterfaceSeedTests/testPrepareAnUnconfiguredGuestWithOriginalExploreFilters',
        cases=['HarborUITests.MusicBillboardNavigationTests/testPublicRanksAlbumChartLocalSearchCountrySelectionAndReturnToGenresOn' + family]))
    captures += ['music-billboard-' + state + '-' + family.lower() for state in ['ranks', 'detail', 'albums', 'search', 'country', 'genres']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-artists', selection_marker=marker,
    selected_case_count=9, pending_native_cases=cases, ui_batches=batches, ui_cases=[row['cases'][0] for row in batches],
    fresh_preparation_executions=4, expected_total_executions=17, expected_original_images=24, required_original_captures=captures,
    new_native_cases=9, new_ui_cases=2, failed_ui_cases_retried=2, retained_explore_native_cases=6, retained_explore_phone_and_tablet_ui_cases=2,
    retained_billboard_native_cases=4, retained_billboard_model_cases=1, retained_billboard_public_native_cases=1,
    retained_music_rust_cases=41, existing_music_rust_tests_repeated=False, retained_reader_native_cases=51,
    unrelated_approved_cases_selected=False, full_music_parity_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Artists:9new native+4fresh+2new UI+2failed Billboard UI=17 executions/24 captures; unrelated approved Music/reader/Rust suites retained. No IPA.')

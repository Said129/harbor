"""Exercise the actual failed public source and three failed journeys, preserving approved parsing and iPad Explore."""
import json
import os
from pathlib import Path

marker = 'affected:music-public-network'
case = 'HarborTests.MusicBillboardPublicTests/testActualPublicHot100KeepsItsPublishedDateRankAndOriginalCatalogIdentity'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() in [marker, case]
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='Billboard' + family, family=family,
        seed='HarborTests.MusicExploreInterfaceSeedTests/testPrepareAnUnconfiguredGuestWithOriginalExploreFilters',
        cases=['HarborUITests.MusicBillboardNavigationTests/testPublicRanksAlbumChartLocalSearchCountrySelectionAndReturnToGenresOn' + family]))
    captures += ['music-billboard-' + state + '-' + family.lower() for state in ['ranks', 'detail', 'albums', 'search', 'country', 'genres']]
batches.append(dict(id='ExploreIPhone', family='IPhone',
    seed='HarborTests.MusicExploreInterfaceSeedTests/testPrepareAnUnconfiguredGuestWithOriginalExploreFilters',
    cases=['HarborUITests.MusicExploreNavigationTests/testOriginalGenresFiltersLibraryIndependenceAndPublicGenreNavigationOnIPhone']))
captures += ['music-explore-' + state + '-iphone' for state in ['genres', 'filtered', 'library', 'genre', 'restored', 'reset']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-public-network', selection_marker=marker,
    selected_case_count=1, pending_native_cases=[case], ui_batches=batches, ui_cases=[row['cases'][0] for row in batches],
    fresh_preparation_executions=3, expected_total_executions=7, expected_original_images=18, required_original_captures=captures,
    failed_native_cases_retried=1, failed_ui_cases_retried=3, new_ui_cases=0,
    selected_rust_cases=['plugin_http::tests::plugin_http_private_mixed_dns_reserved_and_dns64_addresses'],
    required_affected_rust_cases=1, retained_billboard_native_cases=4, retained_billboard_model_cases=1,
    retained_explore_native_cases=6, retained_explore_tablet_ui_case=1, retained_public_catalog_phone_ui_case=1,
    retained_music_rust_cases=41, existing_music_rust_tests_repeated=False, retained_reader_native_cases=51,
    unrelated_approved_cases_selected=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text(case.replace('.', '/', 1) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Public Music repair:1failed native+3fresh+3failed UI=7 executions/18 captures; one changed Rust classifier, other approved suites retained. No IPA.')

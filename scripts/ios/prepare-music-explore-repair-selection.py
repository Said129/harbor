"""Retry the one native and two UI failures from authenticated Explore run 40087561744."""
import json
import os
from pathlib import Path
import re

marker = 'affected:music-explore'
case = 'HarborTests.MusicExploreNativeTests/testOnlyAnonymousProviderGETRequestsRunAndRetiredScopeCannotPublishALateChart'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() in [marker, case]
suite, method = case.split('.', 1)[1].split('/')
assert re.search(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='Explore' + family, family=family,
        seed='HarborTests.MusicExploreInterfaceSeedTests/testPrepareAnUnconfiguredGuestWithOriginalExploreFilters',
        cases=['HarborUITests.MusicExploreNavigationTests/testOriginalGenresFiltersLibraryIndependenceAndPublicGenreNavigationOn' + family]))
    captures += ['music-explore-' + state + '-' + family.lower() for state in ['genres', 'filtered', 'library', 'genre', 'restored', 'reset']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-explore-repair', selection_marker=marker,
    selected_case_count=1, pending_native_cases=[case], ui_batches=batches, ui_cases=[row['cases'][0] for row in batches],
    fresh_preparation_executions=2, expected_total_executions=5, expected_original_images=12, required_original_captures=captures,
    new_native_cases=0, new_ui_cases=0, failed_native_cases_retried=1, failed_ui_cases_retried=2,
    latest_music_run=40087561744, retained_explore_native_cases=5, retained_public_catalog_phone_ui_case=1,
    retained_music_catalog_native_cases=6, retained_music_collection_native_cases=3,
    retained_music_rust_run=40054397288, retained_music_rust_cases=41, existing_rust_tests_repeated=False,
    retained_reader_native_cases=51, unrelated_approved_cases_selected=False,
    full_explore_parity_complete=False, full_music_parity_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text(case.replace('.', '/', 1) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Explore repair:1 failed native+2fresh+2failed UI=5 executions/12 captures; all five new native passes and public catalog phone pass retained. No IPA.')

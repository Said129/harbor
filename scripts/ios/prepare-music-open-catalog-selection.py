"""New native public Music integration and only its new/failed UI paths."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.MusicCatalogModelTests/'
cases = []
for suite, count in [('MusicCatalogModelTests', 3), ('MusicCatalogNativeTests', 2)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = 'HarborTests.HarborNativeNetworkTests/testActualNativeABIDeniesPrivateTargetsBeforeAnyConnection'
cases.append(affected)
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='OpenCatalog' + family, family=family,
        seed='HarborTests.MusicCatalogInterfaceSeedTests/testPrepareAnUnconfiguredGuestForTheActualPublicCatalog',
        cases=['HarborUITests.MusicCatalogNavigationTests/testActualPublicHomeSearchAlbumTracksAndArtistAlbumsOn' + family]))
    batches.append(dict(id='MusicCollections' + family, family=family,
        seed='HarborTests.MusicCollectionInterfaceSeedTests/testPrepareOneOwnedAudioFileInAnUnconfiguredFreshGuest',
        cases=['HarborUITests.MusicCollectionsNavigationTests/testSavedTracksActualPlaybackAndRecentCollectionKeepTheirIndependentContentsOn' + family]))
    captures += ['music-open-' + state + '-' + family.lower() for state in ['home', 'search', 'album', 'artist']]
    captures += ['music-collections-' + state + '-' + family.lower() for state in ['liked', 'playing', 'recent', 'unliked']]
for case in cases + [row['seed'] for row in batches] + [row['cases'][0] for row in batches]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
assert len(cases) == 6 and len(set(captures)) == 16
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-open-catalog', selection_marker=marker,
    selected_case_count=6, pending_native_cases=cases, ui_batches=batches, ui_cases=[row['cases'][0] for row in batches],
    fresh_preparation_executions=4, expected_total_executions=14, expected_original_images=16, required_original_captures=captures,
    new_native_cases=5, changed_approved_native_cases=[affected],
    changed_approved_reason='The HTTP caller now shares the native continuation setup with the typed music caller; keep its actual private-target denial contract',
    new_ui_cases=2, failed_ui_cases_retried=2,
    retained_music_collection_run=40052987527, retained_music_collection_native_cases=3,
    retained_music_rust_run=40054397288, retained_music_rust_cases=41, existing_rust_tests_repeated=False,
    retained_reader_native_cases=51, unrelated_approved_cases_selected=False,
    full_music_parity_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Music catalog:5 NEW native+1 affected HTTP+4fresh+2new/2failedUI=14actual16captures;41 Rust and3 collection models retained. No IPA.')

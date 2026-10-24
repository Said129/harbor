"""Only new saved/recent music contracts and two fresh mobile journeys."""
import json
import os
from pathlib import Path
import re

requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/MusicCollectionsTests.swift').read_text('utf-8'))
assert len(set(methods)) == len(methods) == 3
cases = ['HarborTests.MusicCollectionsTests/' + method for method in methods]
assert requested == 'HarborTests.MusicCollectionsTests/' or requested.split(',') == cases
seed = 'HarborTests.MusicCollectionInterfaceSeedTests/testPrepareOneOwnedAudioFileInAnUnconfiguredFreshGuest'
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    ui = 'HarborUITests.MusicCollectionsNavigationTests/testSavedTracksActualPlaybackAndRecentCollectionKeepTheirIndependentContentsOn' + family
    batches.append(dict(id='MusicCollections' + family, family=family, seed=seed, cases=[ui]))
    captures += ['music-collections-' + state + '-' + family.lower() for state in ['liked', 'playing', 'recent', 'unliked']]
for case in [seed] + [row['cases'][0] for row in batches]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-collections',
    selected_case_count=3, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[row['cases'][0] for row in batches], fresh_preparation_executions=2,
    expected_total_executions=7, expected_original_images=8, required_original_captures=captures,
    new_native_cases=3, new_ui_cases=2, retained_reader_native_models=51,
    prior_music_playback_suite_repeated=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Music collections:3 NEW native+2 fresh+2 new UI=7executions8captures; original complete playback suite retained. No IPA.')

"""Six new cover/cache checks and only three mounts with actual visual findings."""
import json
import os
from pathlib import Path
import re

cases = []
for suite, count in [('MusicPlaylistCoverTests', 4), ('MusicPlaylistCoverMountTests', 1), ('MusicRememberCacheTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = [
    'HarborTests.MusicMixedCollectionMountTests/testMixedPlaylistCompactRowsRecentAndAddTrayMountWithDecodedRemoteMosaicsInBothSizes',
    'HarborTests.MusicServerConnectionMountTests/testProductionPrivateServerFormAndConnectedStateMountInBothNativeSizes',
    'HarborTests.SharedMusicPlaybackMountTests/testActualSharedPlayerMetadataTransportAndQueueMountInBothNativeSizes',
]
cases += affected
marker = 'affected:music-playlist-covers'
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
captures = ['music-' + state + '-cover-' + size for size in ['compact', 'regular'] for state in ['custom', 'cleared']]
captures += ['music-mixed-' + state + '-' + size for size in ['compact', 'regular'] for state in ['playlist', 'compact', 'recent', 'add']]
captures += ['music-server-' + state + '-' + size for size in ['compact', 'regular'] for state in ['form', 'connected']]
captures += ['music-shared-' + state + '-' + size for size in ['compact', 'regular'] for state in ['top', 'queue']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-playlist-covers', selection_marker=marker,
    selected_case_count=9, pending_native_cases=cases, new_native_cases=6, failed_or_affected_cases=affected, ui_cases=[], ui_batches=[],
    fresh_preparation_executions=0, expected_total_executions=9, expected_original_images=20, required_original_captures=captures,
    label_reference='ios/HarborTests/Fixtures/music-playlist-cover-labels.json', label_comparisons=80,
    original_inputs='docs/ios/music-playlist-cover-inputs.json', retained_parent_run=40962758995,
    retained_parent_passes=13, retained_parent_unaffected_native_cases_not_repeated=10,
    ordinary_picker_journey_verified=False, physical_performance_verified=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream:
        stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('6 new cover/cache cases + 3 visually affected mounts; 20 originals; 10 unaffected parent passes retained; no IPA.')

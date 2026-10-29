"""Select new M3U/large collection contracts and three actually affected interfaces."""
import json
import os
from pathlib import Path
import re

cases = []
for suite, count in [('MusicPlaylistExportTests', 4), ('MusicLargeCollectionTests', 2)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = [
    'HarborTests.MusicQueueOrderTests/testTypedQueueInterfaceRetainsPreviewUntilAdvanceAndRecoversAfterRejectedInput',
    'HarborTests.MusicMixedCollectionMountTests/testMixedPlaylistCompactRowsRecentAndAddTrayMountWithDecodedRemoteMosaicsInBothSizes',
    'HarborTests.MusicServerConnectionMountTests/testProductionPrivateServerFormAndConnectedStateMountInBothNativeSizes',
]
cases += affected
marker = 'affected:music-export-large'; requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
captures = ['music-mixed-' + state + '-' + size for size in ['compact', 'regular'] for state in ['playlist', 'compact', 'recent', 'add']]
captures += ['music-server-' + state + '-' + size for size in ['compact', 'regular'] for state in ['form', 'connected']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='music-export-large', selection_marker=marker,
    selected_case_count=9, pending_native_cases=cases, new_native_cases=6, failed_or_affected_cases=affected,
    ui_cases=[], ui_batches=[], fresh_preparation_executions=0, expected_total_executions=9,
    expected_original_images=12, required_original_captures=captures,
    selected_rust_cases=['music::tests::large_playlist_order_preserves_every_member_and_full_transport_ids'],
    required_new_rust_cases=1, rust_results='preserved-music-export-large-rust.json',
    label_reference='ios/HarborTests/Fixtures/music-playlist-export-labels.json', label_comparisons=64,
    original_inputs='docs/ios/music-playlist-export-inputs.json',
    queue_program_sha256='224e1945b940bb26dabb04ffe9aea4761eb16e2de1fa61a8ba10245f71684718',
    retained_nearby_passes=49, retained_unaffected_native_cases_not_repeated=46,
    ordinary_picker_journey_verified=False, physical_performance_verified=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('6 new native cases + 3 affected cases, 1 new Rust case, 12 originals; 46 actual passes retained; no IPA.')

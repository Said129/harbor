"""New shared playback preparation plus only the failed/affected server checks."""
import json
import os
from pathlib import Path
import re
cases=[]
for suite,count in [('MusicQueueOrderTests',2),('MusicPlaybackPreparationTests',3)]:
    methods=re.findall(r'\bfunc (test\w+)\(',Path('ios/HarborTests/'+suite+'.swift').read_text('utf-8'))
    assert len(methods)==len(set(methods))==count
    cases += ['HarborTests.'+suite+'/'+method for method in methods]
affected=[
 'HarborTests.MusicServerCatalogTests/testCombinedHomeSettlesConcurrentlyRetainsGoodSourcesAndCancelsItsBrowseBudget',
 'HarborTests.MusicServerConnectionMountTests/testProductionPrivateServerFormAndConnectedStateMountInBothNativeSizes',
]
cases+=affected
marker='affected:music-playback-preparation'
requested=os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested==marker or requested.split(',')==cases
captures=['music-server-'+state+'-'+size for size in ['compact','regular'] for state in ['form','connected']]
plan=dict(source=os.environ.get('GITHUB_SHA','working-tree'),block='music-playback-preparation',selection_marker=marker,
    selected_case_count=7,pending_native_cases=cases,new_native_cases=5,failed_or_affected_cases=affected,ui_cases=[],ui_batches=[],
    fresh_preparation_executions=0,expected_total_executions=7,expected_original_images=4,required_original_captures=captures,
    original_reference='ios/HarborTests/Fixtures/music-queue-order-reference.json',
    original_native_reference='docs/ios/music-playback-preparation-inputs.json',original_queue_comparisons=610,
    original_queue_class_compiled_complete=True,real_mpv_header_array_test=True,
    actual_music_audio_playback_verified=False,shared_player_engine_connected=False,ordinary_app_route_journey_verified=False,
    unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path('ios/build');build.mkdir(parents=True,exist_ok=True)
(build/'preserved-plugin-integration.json').write_text(json.dumps(plan,indent=2)+'\n','utf-8')
(build/'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.','/',1) for case in cases)+'\n','utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'],'a',encoding='utf-8') as stream:stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('5 new queue/header/session/listening cases + 2 failed/affected server checks; 4 affected captures, no audio or IPA claim.')

"""New mixed collection checks plus the shared player cases not yet executed."""
import json
import os
from pathlib import Path
import re
cases=[]
for suite,count in [('MusicMixedCollectionTests',4),('MusicMixedCollectionMountTests',1),('SharedMusicPlaybackTests',6),('SharedMusicPlaybackMountTests',1)]:
    methods=re.findall(r'\bfunc (test\w+)\(',Path('ios/HarborTests/'+suite+'.swift').read_text('utf-8'))
    assert len(methods)==len(set(methods))==count
    cases+=['HarborTests.'+suite+'/'+method for method in methods]
affected=['HarborTests.MusicServerConnectionMountTests/testProductionPrivateServerFormAndConnectedStateMountInBothNativeSizes']
cases+=affected
marker='affected:music-mixed-collections';requested=os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested==marker or requested.split(',')==cases
captures=['music-mixed-'+state+'-'+size for size in ['compact','regular'] for state in ['playlist','compact','recent','add']]
captures+=['music-shared-'+state+'-'+size for size in ['compact','regular'] for state in ['top','queue']]
captures+=['music-server-'+state+'-'+size for size in ['compact','regular'] for state in ['form','connected']]
plan=dict(source=os.environ.get('GITHUB_SHA','working-tree'),block='music-mixed-collections',selection_marker=marker,
    selected_case_count=13,pending_native_cases=cases,new_native_cases=5,prior_shared_cases_not_executed=8,failed_or_affected_cases=affected,ui_cases=[],ui_batches=[],
    fresh_preparation_executions=0,expected_total_executions=13,expected_original_images=16,required_original_captures=captures,
    original_reference='ios/HarborTests/Fixtures/music-collection-tools-reference.json',original_comparisons=60,
    label_reference='ios/HarborTests/Fixtures/music-mixed-collection-labels.json',new_label_comparisons=592,
    prior_player_label_reference='ios/HarborTests/Fixtures/music-shared-player-labels.json',prior_player_label_comparisons=432,
    retained_nearby_passes=31,retained_unaffected_native_cases_not_repeated=30,
    actual_loopback_and_imported_audio_execution_required=True,ordinary_app_route_journey_verified=False,
    unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path('ios/build');build.mkdir(parents=True,exist_ok=True)
(build/'preserved-plugin-integration.json').write_text(json.dumps(plan,indent=2)+'\n','utf-8')
(build/'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.','/',1) for case in cases)+'\n','utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'],'a',encoding='utf-8') as stream:stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('5 new mixed-collection checks + 8 unexecuted shared-player checks; 16 originals, 30 approved checks retained; no IPA.')

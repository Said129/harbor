"""Only new private-server catalog integration, connection forms and their labels."""
import json
import os
from pathlib import Path
import re
cases=[]
for suite,count in [('MusicServerCatalogTests',6),('MusicServerConnectionMountTests',1)]:
    methods=re.findall(r'\bfunc (test\w+)\(',Path('ios/HarborTests/'+suite+'.swift').read_text('utf-8'))
    assert len(methods)==len(set(methods))==count
    cases += ['HarborTests.'+suite+'/'+method for method in methods]
affected='HarborTests.SubsonicMusicServiceTests/testOriginalHomePartialFailureSearchAlbumOrderArtistFanoutAndPlaylistOrder'
cases.append(affected)
marker='affected:music-server-catalog'
requested=os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested==marker or requested.split(',')==cases
captures=['music-server-'+state+'-'+size for size in ['compact','regular'] for state in ['form','connected']]
plan=dict(source=os.environ.get('GITHUB_SHA','working-tree'),block='music-server-catalog',selection_marker=marker,
    selected_case_count=8,pending_native_cases=cases,new_native_cases=7,affected_native_cases=[affected],ui_cases=[],ui_batches=[],
    fresh_preparation_executions=0,expected_total_executions=8,expected_original_images=4,required_original_captures=captures,
    original_reference='ios/HarborTests/Fixtures/music-server-catalog-reference.json',owned_private_server_transport=True,
    live_private_server_requests_performed=False,actual_music_audio_playback_verified=False,
    native_server_form_and_shared_catalog_routes_implemented=True,ordinary_app_route_journey_verified=False,
    previously_approved_server_transport_cases_selected=1,unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_music_connections_interface_completed=False,full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path('ios/build');build.mkdir(parents=True,exist_ok=True)
(build/'preserved-plugin-integration.json').write_text(json.dumps(plan,indent=2)+'\n','utf-8')
(build/'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.','/',1) for case in cases)+'\n','utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'],'a',encoding='utf-8') as stream:stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('7 new server catalog/form/label/mount cases + 1 affected fan-out case, 4 original captures. Eighteen other approved cases retained.')

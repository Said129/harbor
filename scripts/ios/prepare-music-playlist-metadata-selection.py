"""Only the new full-recording persistence and genuinely changed playlist transaction paths."""
import json
import os
from pathlib import Path
import re
suite="MusicPlaylistMetadataTests"
methods=re.findall(r"\bfunc (test\w+)\(",Path("ios/HarborTests/"+suite+".swift").read_text("utf-8"))
assert len(methods)==len(set(methods))==4
cases=["HarborTests."+suite+"/"+method for method in methods]
marker="affected:music-playlist-metadata"
requested=os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested==marker or requested.split(",")==cases
plan=dict(source=os.environ.get("GITHUB_SHA","working-tree"),block="music-playlist-metadata",selection_marker=marker,
    selected_case_count=4,pending_native_cases=cases,new_native_cases=4,ui_cases=[],ui_batches=[],
    fresh_preparation_executions=0,expected_total_executions=4,expected_original_images=0,required_original_captures=[],
    original_reference="ios/HarborTests/Fixtures/music-playlist-metadata-reference.json",
    actual_original_database_sql_fragments_executed=True,complete_original_rust_function_executed=False,
    existing_music_player_changed=False,mixed_playlist_interface_complete=False,remote_music_source_playback_complete=False,
    unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path("ios/build");build.mkdir(parents=True,exist_ok=True)
(build/"preserved-plugin-integration.json").write_text(json.dumps(plan,indent=2)+"\n","utf-8")
(build/"plugin-integration-selection.txt").write_text("\n".join(case.replace(".","/",1) for case in cases)+"\n","utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"],"a",encoding="utf-8") as stream:stream.write("HARBOR_PLUGIN_UI_REQUIRED=false\n")
print("4 new playlist metadata/transaction/migration cases; unrelated approved audio/UI cases retained.")

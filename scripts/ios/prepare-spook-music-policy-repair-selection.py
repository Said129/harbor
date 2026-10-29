"""Two failed original-world contracts and the newly ported music policy only."""
import json
import os
from pathlib import Path
import re
failed=[
    "HarborTests.SpooktoberWorldTests/testSixteenExecutedDesktopIntentsAndMusicMappingsRetainIdentityPayloadAndAllowedPlaylists",
    "HarborTests.SpooktoberWorldMountTests/testRealWorldBridgeCannotWriteOrRouteAfterTheProfileLeaseEnds",
]
for case in failed:
    suite,method=case.removeprefix("HarborTests.").split("/")
    assert "func "+method+"(" in Path("ios/HarborTests/"+suite+".swift").read_text("utf-8")
methods=re.findall(r"\bfunc (test\w+)\(",Path("ios/HarborTests/MusicSourcePolicyTests.swift").read_text("utf-8"))
assert len(methods)==len(set(methods))==2
cases=failed+["HarborTests.MusicSourcePolicyTests/"+method for method in methods]
marker="affected:spook-music-policy-repair"
requested=os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested==marker or requested.split(",")==cases
plan=dict(source=os.environ.get("GITHUB_SHA","working-tree"),block="spook-music-policy-repair",selection_marker=marker,
    selected_case_count=4,pending_native_cases=cases,new_native_cases=2,repaired_native_cases=failed,ui_cases=[],ui_batches=[],
    fresh_preparation_executions=0,expected_total_executions=4,expected_original_images=0,required_original_captures=[],
    original_reference="ios/HarborTests/Fixtures/music-source-policy-reference.json",original_world_reference="ios/HarborTests/Fixtures/spooktober-world-reference.json",
    retained_original_world_native_passes=5,retained_music_metadata_native_passes=4,previous_originals_reviewed=12,
    previous_originals_visually_approved=False,ordinary_app_navigation_verified=False,
    remote_music_source_playback_completed=False,mixed_playlist_interface_completed=False,
    unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path("ios/build");build.mkdir(parents=True,exist_ok=True)
(build/"preserved-plugin-integration.json").write_text(json.dumps(plan,indent=2)+"\n","utf-8")
(build/"plugin-integration-selection.txt").write_text("\n".join(case.replace(".","/",1) for case in cases)+"\n","utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"],"a",encoding="utf-8") as stream:stream.write("HARBOR_PLUGIN_UI_REQUIRED=false\n")
print("2 failed world contracts + 2 new Apple music policy cases; 5 world and 4 metadata passes retained.")

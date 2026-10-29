"""Only the new private-server music request, storage and profile lifetime contracts."""
import json
import os
from pathlib import Path
import re
suite="SubsonicMusicServiceTests"
methods=re.findall(r"\bfunc (test\w+)\(",Path("ios/HarborTests/"+suite+".swift").read_text("utf-8"))
assert len(methods)==len(set(methods))==6
cases=["HarborTests."+suite+"/"+method for method in methods]
marker="affected:subsonic-music"
requested=os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested==marker or requested.split(",")==cases
plan=dict(source=os.environ.get("GITHUB_SHA","working-tree"),block="subsonic-music",selection_marker=marker,
    selected_case_count=6,pending_native_cases=cases,new_native_cases=6,ui_cases=[],ui_batches=[],
    fresh_preparation_executions=0,expected_total_executions=6,expected_original_images=0,required_original_captures=[],
    original_reference="docs/ios/subsonic-reference-inputs.json",owned_private_server_transport=True,
    live_private_server_requests_performed=False,actual_music_audio_playback_verified=False,
    music_connection_interface_completed=False,ordinary_app_provider_routing_completed=False,
    unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path("ios/build");build.mkdir(parents=True,exist_ok=True)
(build/"preserved-plugin-integration.json").write_text(json.dumps(plan,indent=2)+"\n","utf-8")
(build/"plugin-integration-selection.txt").write_text("\n".join(case.replace(".","/",1) for case in cases)+"\n","utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"],"a",encoding="utf-8") as stream:stream.write("HARBOR_PLUGIN_UI_REQUIRED=false\n")
print("6 new Subsonic request/catalog/profile/Keychain cases; approved source policy and playlist cases retained.")

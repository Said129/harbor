"""Only the newly prepared original seasonal world runtime and native adapters."""
import json
import os
from pathlib import Path
import re
cases=[]
for suite,count in [("SpooktoberWorldTests",3),("SpooktoberWorldMountTests",2)]:
    methods=re.findall(r"\bfunc (test\w+)\(",Path("ios/HarborTests/"+suite+".swift").read_text("utf-8"))
    assert len(methods)==len(set(methods))==count
    cases += ["HarborTests."+suite+"/"+method for method in methods]
marker="affected:spooktober-world"
requested=os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested==marker or requested.split(",")==cases
captures=["spook-world-"+state+"-"+size for size in ["compact","regular"] for state in ["home","catalog","books","book-detail"]]
plan=dict(source=os.environ.get("GITHUB_SHA","working-tree"),block="spooktober-world",selection_marker=marker,
    selected_case_count=5,pending_native_cases=cases,new_native_cases=5,ui_cases=[],ui_batches=[],
    fresh_preparation_executions=0,expected_total_executions=5,expected_original_images=8,
    required_original_captures=captures,original_reference="ios/HarborTests/Fixtures/spooktober-world-reference.json",
    original_runtime_assets="ios/Harbor/SpooktoberWorldAssets.json",
    actual_original_world_runs_in_webkit=True,ordinary_app_navigation_verified=False,
    existing_room_replacement_wired=False,playlist_native_surface_completed=False,music_source_playback_completed=False,
    personal_account_requests_performed=False,retained_approved_home_entry_cases=True,
    unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path("ios/build");build.mkdir(parents=True,exist_ok=True)
(build/"preserved-plugin-integration.json").write_text(json.dumps(plan,indent=2)+"\n","utf-8")
(build/"plugin-integration-selection.txt").write_text("\n".join(case.replace(".","/",1) for case in cases)+"\n","utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"],"a",encoding="utf-8") as stream:stream.write("HARBOR_PLUGIN_UI_REQUIRED=false\n")
print("5 new original-world resource/intent/persistence/native WebKit cases, 8 originals; no replay of approved Home entry or Trakt cases.")

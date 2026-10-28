"""Only the new personalized Trakt Home contracts and actual native surfaces."""
import json
import os
from pathlib import Path
import re
cases=[]
for suite,count in [("TraktHomeTests",4),("TraktHomeMountTests",1)]:
    methods=re.findall(r"\bfunc (test\w+)\(",Path("ios/HarborTests/"+suite+".swift").read_text("utf-8"))
    assert len(methods)==len(set(methods))==count
    cases += ["HarborTests."+suite+"/"+method for method in methods]
marker="affected:trakt-home"
requested=os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested==marker or requested.split(",")==cases
captures=["trakt-home-"+state+"-"+size for size in ["compact","regular"] for state in ["watchlist","recommendations","view-all","customization"]]
plan=dict(source=os.environ.get("GITHUB_SHA","working-tree"),block="trakt-home",selection_marker=marker,
    selected_case_count=5,pending_native_cases=cases,new_native_cases=5,ui_cases=[],ui_batches=[],
    fresh_preparation_executions=0,expected_total_executions=5,expected_original_images=8,
    required_original_captures=captures,original_reference="ios/HarborTests/Fixtures/trakt-home-reference.json",
    actual_production_swiftui_surfaces=True,ordinary_app_navigation_verified=False,
    personal_account_requests_performed=False,retained_approved_trakt_library_cases=True,
    unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path("ios/build");build.mkdir(parents=True,exist_ok=True)
(build/"preserved-plugin-integration.json").write_text(json.dumps(plan,indent=2)+"\n","utf-8")
(build/"plugin-integration-selection.txt").write_text("\n".join(case.replace(".","/",1) for case in cases)+"\n","utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"],"a",encoding="utf-8") as stream:stream.write("HARBOR_PLUGIN_UI_REQUIRED=false\n")
print("5 new Trakt Home contracts/native surfaces, 8 originals; no replay of approved Trakt library/OAuth/scrobble or Home journeys.")

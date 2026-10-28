"""New origin routing plus the affected native merge and two observed UI findings."""
import json
import os
from pathlib import Path
import re
marker = "affected:addon-origins"
suite = "AddonOriginTests"
methods = re.findall(r"\bfunc (test\w+)\(", Path("ios/HarborTests/" + suite + ".swift").read_text("utf-8"))
assert len(methods) == len(set(methods)) == 7
cases = ["HarborTests." + suite + "/" + method for method in methods]
affected = ["HarborTests.HarborPluginStreamSourceTests/testActualDetailSelectionMergesPluginWorkersThroughOriginalAdapterRankingAndDirectSubtitleResolution"]
cases += affected
requested = os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested == marker or requested.split(",") == cases
batches, captures = [], []
for family in ["IPhone", "IPad"]:
    batches.append(dict(id="OriginUI" + family, family=family,
        seed="HarborTests.CustomListInterfaceSeedTests/testPrepareOwnedListsForBothRealLibraryInterfacesOnAFreshGuest",
        cases=["HarborExistingAppUITests.CustomListLocalizationNavigationTests/testFreshListTimestampAndDetailActionsUseTheSelectedEnglishLanguageOn" + family]))
    captures += [prefix + "-" + family.lower() for prefix in ["custom-list-recent-localized", "custom-list-detail-localized"]]
for case in cases + [case for batch in batches for case in [batch["seed"], *batch["cases"]]]:
    target, tail = case.split(".", 1); suite, method = tail.split("/")
    target = "HarborUITests" if target == "HarborExistingAppUITests" else target
    assert len(re.findall(r"\bfunc " + method + r"\(", Path("ios/" + target + "/" + suite + ".swift").read_text("utf-8"))) == 1
plan = dict(source=os.environ.get("GITHUB_SHA", "working-tree"), block="addon-origins", selection_marker=marker,
    selected_case_count=8, pending_native_cases=cases, new_native_cases=7, affected_native_cases=affected,
    affected_native_reason="HarborService.streams and plugin source selection changed; exercise their real merge/adapter/ranking path.",
    ui_batches=batches, ui_cases=[case for batch in batches for case in batch["cases"]], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=12, expected_original_images=4, required_original_captures=captures,
    original_reference="ios/HarborTests/Fixtures/addon-origin-reference.json",
    preserved_parent_run=40691573028, preserved_parent_source="13675f57f1f5f7527305d1574675828d7a7607cc",
    collect_launch_failure_diagnostics=True, personal_account_requests_performed=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path("ios/build"); build.mkdir(parents=True, exist_ok=True)
(build / "preserved-plugin-integration.json").write_text(json.dumps(plan, indent=2)+"\n", "utf-8")
(build / "plugin-integration-selection.txt").write_text("\n".join(case.replace(".", "/", 1) for case in cases)+"\n", "utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream: stream.write("HARBOR_PLUGIN_UI_REQUIRED=true\n")
print("7 new origins +1 affected native merge +2 fresh preparations +2 targeted UI routes=12 executions/4 originals; no unrelated replay or IPA.")

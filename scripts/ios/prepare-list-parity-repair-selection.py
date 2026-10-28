"""Select the actual failed list/origin cases, two affected reset/plan paths and failed iPad UI."""
import json
import os
from pathlib import Path
import re

marker = "affected:list-parity-repair"
selected = [
    "HarborTests.CustomListHomeTests/testActualDesktopAddRemoveAndRowOptionsPersistAndResetWithoutDeletingLists",
    "HarborTests.AddonOriginTests/testExecutedDesktopOriginBasesNativeIDsAlternateTypesAndPluginBasesMatch",
    "HarborTests.CustomListHomeTests/testRawListReferencesRetainMissingRowsAndRejectStaleOrMalformedEditsWithoutReplacingSavedData",
    "HarborTests.AddonOriginTests/testOriginStreamRequestsKeepOtherProvidersRawEpisodeAndDeclaredTypeFallback",
]
requested = os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested == marker or requested.split(",") == selected
ui = "HarborExistingAppUITests.CustomListLocalizationNavigationTests/testFreshListTimestampAndDetailActionsUseTheSelectedEnglishLanguageOnIPad"
seed = "HarborTests.CustomListInterfaceSeedTests/testPrepareOwnedListsForBothRealLibraryInterfacesOnAFreshGuest"
for case in selected + [ui, seed]:
    target, tail = case.split(".", 1); suite, method = tail.split("/")
    target = "HarborUITests" if target == "HarborExistingAppUITests" else target
    assert len(re.findall(r"\bfunc " + method + r"\(", Path("ios/" + target + "/" + suite + ".swift").read_text("utf-8"))) == 1
plan = dict(source=os.environ.get("GITHUB_SHA", "working-tree"), block="list-parity-repair", selection_marker=marker,
    selected_case_count=4, pending_native_cases=selected, failed_native_cases=selected[:2], affected_native_cases=selected[2:],
    affected_native_reason="Reset also preserves future fields/independent ownership; moving duplicate-type suppression into actual request planning affects the selected fallback path.",
    ui_batches=[dict(id="ListLocaleRepairIPad", family="IPad", seed=seed, cases=[ui])], ui_cases=[ui],
    single_family_repair=True, repair_family="IPad", failed_ui_case=ui,
    preserve_prepared_app_data=True, fresh_preparation_executions=1, expected_total_executions=6,
    expected_original_images=2, required_original_captures=["custom-list-recent-localized-ipad", "custom-list-detail-localized-ipad"],
    preserved_home_run=40739389865, preserved_home_source="28386ee04c67a435b627e28bae1a6ea6899d341c",
    preserved_origin_run=40740807507, preserved_origin_source="baf87971970e0109a15328a64a637f5c7fc9e64e",
    original_references=["ios/HarborTests/Fixtures/home-lists-reference.json", "ios/HarborTests/Fixtures/addon-origin-reference.json"],
    retained_full_home_ui_cases=True, retained_iphone_localization_ui=True, collect_launch_failure_diagnostics=True,
    personal_account_requests_performed=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path("ios/build"); build.mkdir(parents=True, exist_ok=True)
(build / "preserved-plugin-integration.json").write_text(json.dumps(plan, indent=2)+"\n", "utf-8")
(build / "plugin-integration-selection.txt").write_text("\n".join(case.replace(".", "/", 1) for case in selected)+"\n", "utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream: stream.write("HARBOR_PLUGIN_UI_REQUIRED=true\n")
print("2 failed native +2 affected native +1 fresh iPad +1 failed iPad UI=6 executions/2 originals. Retain both approved Home journeys and the approved iPhone locale journey.")

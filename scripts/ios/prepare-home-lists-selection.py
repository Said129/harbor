"""New home-list contracts, affected wire preservation and real iPhone/iPad journeys."""
import json
import os
from pathlib import Path
import re

marker = "affected:home-lists"
cases = []
for suite, count in [("CustomListHomeTests", 5), ("CustomListMangaArtworkTests", 1)]:
    methods = re.findall(r"\bfunc (test\w+)\(", Path("ios/HarborTests/" + suite + ".swift").read_text("utf-8"))
    assert len(methods) == len(set(methods)) == count
    cases += ["HarborTests." + suite + "/" + method for method in methods]
affected = ["HarborTests.DesktopPageLayoutTests/testEditingHomePreservesUnsupportedRowsListsCustomSourcesFutureFieldsAndUnchangedLongDesktopNames"]
cases += affected
requested = os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested == marker or requested.split(",") == cases
batches, captures = [], ["native-home-manga-cover"]
for family in ["IPhone", "IPad"]:
    batches.append(dict(id="HomeLists" + family, family=family,
        seed="HarborTests.CustomListHomeSeedTests/testPrepareOwnedMovieMangaAndEmptyListsForTheRealHomeOnAFreshGuest",
        cases=["HarborExistingAppUITests.CustomListHomeNavigationTests/testHomeListsCustomizeRestoreAndReadTheirOwnedPDFOn" + family]))
    captures += [prefix + "-" + family.lower() for prefix in ["home-lists-added", "home-lists-restored", "home-list-manga-hero", "home-list-manga-reader"]]
for case in cases + [case for batch in batches for case in [batch["seed"], *batch["cases"]]]:
    target, tail = case.split(".", 1); suite, method = tail.split("/")
    target = "HarborUITests" if target == "HarborExistingAppUITests" else target
    assert len(re.findall(r"\bfunc " + method + r"\(", Path("ios/" + target + "/" + suite + ".swift").read_text("utf-8"))) == 1
plan = dict(source=os.environ.get("GITHUB_SHA", "working-tree"), block="home-lists", selection_marker=marker,
    selected_case_count=7, pending_native_cases=cases, new_native_cases=6, affected_native_cases=affected,
    affected_native_reason="The wire map now registers saved listRows, including absent and empty lists; retain unsupported fields and custom sources.",
    ui_batches=batches, ui_cases=[case for batch in batches for case in batch["cases"]], preserve_prepared_app_data=True,
    owned_local_source_ui_server=True, fresh_preparation_executions=2, expected_total_executions=11,
    expected_original_images=9, required_original_captures=captures,
    original_reference="ios/HarborTests/Fixtures/home-lists-reference.json",
    preserved_parent_run=40691573028, preserved_parent_source="13675f57f1f5f7527305d1574675828d7a7607cc",
    collect_launch_failure_diagnostics=True, personal_account_requests_performed=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path("ios/build"); build.mkdir(parents=True, exist_ok=True)
(build / "preserved-plugin-integration.json").write_text(json.dumps(plan, indent=2)+"\n", "utf-8")
(build / "plugin-integration-selection.txt").write_text("\n".join(case.replace(".", "/", 1) for case in cases)+"\n", "utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream: stream.write("HARBOR_PLUGIN_UI_REQUIRED=true\n")
print("6 new native +1 affected wire contract +2 fresh guests +2 new Home journeys=11 executions/9 originals; no unrelated replay or IPA.")

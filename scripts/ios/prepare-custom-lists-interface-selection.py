"""New list interface contracts and fresh actual iPhone/iPad journeys only."""
import json
import os
from pathlib import Path
import re

marker = "affected:custom-lists-interface"
suite = "CustomListInterfaceContractsTests"
methods = re.findall(r"\bfunc (test\w+)\(", Path("ios/HarborTests/" + suite + ".swift").read_text("utf-8"))
assert len(methods) == len(set(methods)) == 3
cases = ["HarborTests." + suite + "/" + method for method in methods]
requested = os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested == marker or requested.split(",") == cases
batches, captures = [], []
for family in ["IPhone", "IPad"]:
    batches.append(dict(id="CustomLists" + family, family=family,
        seed="HarborTests.CustomListInterfaceSeedTests/testPrepareOwnedListsForBothRealLibraryInterfacesOnAFreshGuest",
        cases=["HarborExistingAppUITests.CustomListNavigationTests/testOwnedListsCreateEditOrderMembershipRemoveAndRestoreOn" + family]))
    captures += [prefix + "-" + family.lower() for prefix in ["custom-lists-cards", "custom-list-detail", "custom-list-created", "custom-list-membership"]]
for case in cases + [case for batch in batches for case in [batch["seed"], *batch["cases"]]]:
    target, tail = case.split(".", 1); suite, method = tail.split("/")
    target = "HarborUITests" if target == "HarborExistingAppUITests" else target
    assert len(re.findall(r"\bfunc " + method + r"\(", Path("ios/" + target + "/" + suite + ".swift").read_text("utf-8"))) == 1
plan = dict(source=os.environ.get("GITHUB_SHA", "working-tree"), block="custom-lists-interface", selection_marker=marker,
    selected_case_count=3, pending_native_cases=cases, new_native_cases=3, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch["cases"]], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=7, expected_original_images=8,
    required_original_captures=captures, original_reference="ios/HarborTests/Fixtures/custom-list-interface-reference.json",
    preserved_parent_run=40685530173, preserved_parent_source="e3ef940a0ab8a8e1766f808a2a026639c6be4ba0",
    collect_launch_failure_diagnostics=True, personal_account_requests_performed=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    native_custom_lists_interface_complete=False, full_desktop_parity_complete=False,
    physical_performance_verified=False, ipa_requested=False)
build = Path("ios/build"); build.mkdir(parents=True, exist_ok=True)
(build / "preserved-plugin-integration.json").write_text(json.dumps(plan, indent=2) + "\n", "utf-8")
(build / "plugin-integration-selection.txt").write_text("\n".join(case.replace(".", "/", 1) for case in cases) + "\n", "utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
        stream.write("HARBOR_PLUGIN_UI_REQUIRED=true\n")
print("Three new list contracts +2 fresh preparations +2 new real interfaces=7 executions/8 originals; no approved replay or IPA.")

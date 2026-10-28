"""Only new Home labels and the seasonal entry's collapsed/reopen route."""
import json
import os
from pathlib import Path
import re
marker="affected:home-entry-language"
cases=["HarborTests.HomeEntryLanguageTests/testAllSixteenDesktopCatalogsResolveTheHeroAndSeasonalInvitationLabels"]
requested=os.environ["HARBOR_NATIVE_SELECTION"].strip()
assert requested==marker or requested.split(",")==cases
batches=[]; captures=[]
for family in ["IPhone","IPad"]:
    batches.append(dict(id="HomeEntry"+family,family=family,
        seed="HarborTests.HomeEntryLanguageSeedTests/testPrepareOwnedMovieAndMangaHeroesWithAnExpandedSeasonalEntryOnAFreshGuest",
        cases=["HarborExistingAppUITests.HomeEntryLanguageNavigationTests/testHeroLabelsAndCollapsedSeasonalEntryStayEnglishAndReopenOn"+family]))
    captures += [prefix+"-"+family.lower() for prefix in ["home-labels-movie","home-labels-expanded","home-labels-collapsed","home-labels-reopened"]]
for case in cases+[case for batch in batches for case in [batch["seed"],*batch["cases"]]]:
    target,tail=case.split(".",1);suite,method=tail.split("/")
    target="HarborUITests" if target=="HarborExistingAppUITests" else target
    assert len(re.findall(r"\bfunc "+method+r"\(",Path("ios/"+target+"/"+suite+".swift").read_text("utf-8")))==1
plan=dict(source=os.environ.get("GITHUB_SHA","working-tree"),block="home-entry-language",selection_marker=marker,
    selected_case_count=1,pending_native_cases=cases,new_native_cases=1,ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch["cases"]],fresh_preparation_executions=2,
    preserve_prepared_app_data=True,owned_local_source_ui_server=True,expected_total_executions=5,
    expected_original_images=8,required_original_captures=captures,
    original_reference="ios/HarborTests/Fixtures/home-labels-reference.json",
    preserved_home_run=40739389865,preserved_home_source="28386ee04c67a435b627e28bae1a6ea6899d341c",
    retained_full_home_journeys=True,retained_reader_and_private_cover_tests=True,
    collect_launch_failure_diagnostics=True,personal_account_requests_performed=False,
    unrelated_approved_cases_selected=False,existing_rust_tests_repeated=False,
    full_seasonal_room_interface_verified=False,full_desktop_parity_complete=False,physical_performance_verified=False,ipa_requested=False)
build=Path("ios/build");build.mkdir(parents=True,exist_ok=True)
(build/"preserved-plugin-integration.json").write_text(json.dumps(plan,indent=2)+"\n","utf-8")
(build/"plugin-integration-selection.txt").write_text("\n".join(case.replace(".","/",1) for case in cases)+"\n","utf-8")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"],"a",encoding="utf-8") as stream:stream.write("HARBOR_PLUGIN_UI_REQUIRED=true\n")
print("1 new locale contract +2 fresh guests +2 focused label/collapse/reopen journeys=5 executions/8 originals; approved full Home and reader journeys retained.")

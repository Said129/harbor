"""New collection preparation and only failed or affected mounted behavior."""
import json
import os
from pathlib import Path
import re

block = 'collection-source-completion'
marker = 'affected:' + block
suite = 'SimklCollectionIndexTests'
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 3
cases = ['HarborTests.' + suite + '/' + method for method in methods]
retained = [
    'HarborTests.PosterBehaviorMountTests/testActualNativeFocusLoadsWidePixelsReservesWidthRevealsTheCardAndCollapsesForPointerWithoutActivatingIt',
    'HarborTests.SimklLibraryContractTests/testAnimeGroupingKeepsFilmFranchisesStatusesCountsCoverFallbacksAndSearchTogether',
    'HarborTests.SimklLibraryMountTests/testProductionLibraryAndHalfStarActionsRenderInCompactAndRegularNativeLayouts',
]
cases += retained
affected_hydration = 'HarborTests.TrackerEpisodeResolverTests/testSixHydrationPathsForceCinemetaAndBridgeForeignShowIdsLikeTheExecutedDesktop'
cases.append(affected_hydration)
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='SourceCollectionCompletion' + family, family=family,
        seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount',
        cases=['HarborExistingAppUITests.CustomSourceNavigationTests/testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOn' + family]))
    captures += ['source-' + state + '-' + family.lower() for state in ['import-dialog', 'fetch-error', 'format-error', 'imported', 'catalog', 'missing-key', 'missing-addon', 'image-editor', 'images-edited', 'hidden', 'restored', 'deleted']]
captures += ['poster-behavior-native-' + state for state in ['initial', 'focused-wide', 'revealed-last', 'pointer-dock']]
captures += ['simkl-library-native-' + state + '-' + size for state in ['movies', 'anime', 'actions', 'settings'] for size in ['compact', 'regular']]
for case in cases + [case for batch in batches for case in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(cases) == len(set(cases)) == 7 and len(captures) == len(set(captures)) == 36
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=7, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=11,
    expected_original_images=36, required_original_captures=captures,
    new_collection_cases=3, failed_native_cases_retried=1, failed_source_ui_cases_retried=2,
    affected_native_cases=retained[1:], parent_partial_run=40436947526,
    affected_hydration_case=affected_hydration, retained_tracker_parent_run=40438838307,
    owned_local_source_ui_server=True, unchanged_profile_and_disk_cases_replayed=False,
    actual_native_focus_and_decoded_pixels_required=True, actual_source_taps_and_reopened_urls_required=True,
    physical_performance_verified=False, actual_ipad_ui_journey_verified=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('3 new collection cases +1 failed native +3 affected native +2 guests +2 failed UI:11 executions/36captures. No IPA.')

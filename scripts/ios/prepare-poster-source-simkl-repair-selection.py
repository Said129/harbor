"""Retry six actual failures and one capture affected by decoded-cover readiness."""
import json
import os
from pathlib import Path
import re

block = 'poster-source-simkl-repair'
marker = 'affected:' + block
cases = [
    'HarborTests.PosterBehaviorProfileTests/testBehaviorSettingsAreIsolatedPerProfileAndSurviveReopeningTheSettingsStore',
    'HarborTests.PosterBehaviorMountTests/testActualNativeFocusLoadsWidePixelsReservesWidthRevealsTheCardAndCollapsesForPointerWithoutActivatingIt',
    'HarborTests.SimklLibraryPersistenceTests/testActualPrivateDiskPersistsPerOwnerAndTokenFingerprintWithoutWritingCredentials',
    'HarborTests.SimklLibraryPersistenceTests/testRatingPreferenceFollowsItsProfileAndThePortableDocumentCannotContainTheAccountToken',
    'HarborTests.SimklLibraryMountTests/testProductionLibraryAndHalfStarActionsRenderInCompactAndRegularNativeLayouts',
]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='SourceFinalRepair' + family, family=family,
        seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount',
        cases=['HarborExistingAppUITests.CustomSourceNavigationTests/testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOn' + family]))
    captures += ['source-' + state + '-' + family.lower() for state in ['import-dialog', 'fetch-error', 'format-error', 'imported', 'catalog', 'missing-key', 'missing-addon', 'image-editor', 'images-edited', 'hidden', 'restored', 'deleted']]
captures += ['poster-behavior-native-' + state for state in ['initial', 'focused-wide', 'revealed-last', 'pointer-dock']]
captures += ['simkl-library-native-' + state + '-' + size for state in ['movies', 'anime', 'actions', 'settings'] for size in ['compact', 'regular']]
for case in cases + [case for batch in batches for case in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(cases) == len(set(cases)) == 5 and len(captures) == len(set(captures)) == 36
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=5, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=9,
    expected_original_images=36, required_original_captures=captures,
    failed_native_cases_retried=4, failed_source_ui_cases_retried=2, affected_capture_case=cases[-1],
    parent_partial_runs=[40407688399, 40414484295], owned_local_source_ui_server=True,
    approved_appearance_and_authorization_ui_replayed=False, file_protection_physical_device_verification_required=True,
    actual_native_focus_and_decoded_pixels_required=True, actual_ipad_ui_journey_verified=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Four failed native cases, one affected capture, two fresh guests and two failed source journeys: 9 executions/36 captures. No IPA.')

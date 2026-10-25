"""Keep authenticated source-model passes and exercise new/failed/affected interface behavior."""
import json
import os
from pathlib import Path
import re

block = 'custom-source-interface'
marker = 'affected:' + block
cases = []
for suite, count in [('CustomSourceRequirementTests', 2), ('DesktopGridPagingTests', 2), ('SourceFocusAnimationTests', 1)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8').split('final class ' + suite + ': XCTestCase {', 1)[1]
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
failed = {'CustomSourceStorageTests': ['testAnImportOpenedForAnOlderScopeAndAnOversizedPayloadCannotChangeTheCurrentSavedSourceRows']}
for suite, methods in failed.items():
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    for method in methods:
        assert len(re.findall(r'\bfunc ' + method + r'\(', source)) == 1
        cases.append('HarborTests.' + suite + '/' + method)
assert len(cases) == len(set(cases)) == 6
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    method = 'testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOn' + family
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/HarborUITests/CustomSourceNavigationTests.swift').read_text('utf-8'))) == 1
    batches.append(dict(id='SourceInterface' + family, family=family,
        seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount',
        cases=['HarborExistingAppUITests.CustomSourceNavigationTests/' + method]))
    captures += ['source-' + state + '-' + family.lower() for state in ['import-dialog', 'fetch-error', 'format-error', 'imported', 'catalog', 'missing-key', 'missing-addon', 'image-editor', 'images-edited', 'hidden', 'restored', 'deleted']]
assert len(captures) == len(set(captures)) == 24
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=6, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=10,
    expected_original_images=24, required_original_captures=captures,
    new_native_cases=4, affected_gif_cases=1, corrected_failed_native_cases=1,
    retained_parent_run=40239615319, retained_parent_source='dedbd9e9111f2980d1bf1a81275e44b3f18fbce7',
    parent_native_passed=29, parent_native_failed=1, retained_unaffected_parent_native=28,
    previous_ui_attempts_failed_before_any_required_capture=True, owned_local_source_ui_server=True,
    duplicate_catalog_pages_must_advance_raw_offsets=True, public_trakt_case_retained_without_replay=True,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Source interface:4NEW+1AFFECTED GIF+1corrected FAILED native+2fresh+2affectedUI=10executions/24captures. Retain28unaffected native passes. No IPA.')

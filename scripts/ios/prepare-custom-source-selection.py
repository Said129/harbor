"""Select new source folders and only affected page persistence/synchronization cases."""
import json
import os
from pathlib import Path
import re

requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
repair = requested == 'affected:custom-sources-repair'
block = 'custom-sources-repair' if repair else 'custom-sources'
marker = 'affected:' + block
cases = []
for suite, count in [('DesktopCustomSourceTests', 3), ('CustomSourceStorageTests', 7 if repair else 6), ('CustomSourceProviderTests', 3), ('SourceFocusAnimationTests', 1), ('PageCustomizationScopeTests', 5)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8').split('final class ' + suite + ': XCTestCase {', 1)[1]
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    if not repair:
        methods = [method for method in methods if method != 'testFirstSignInParksGuestSourceRowsWhenTheAccountWinsAndAnAbsentAccountWaitsForAnExplicitEdit']
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = {
    'PageLayoutSyncTests': [
        'testFirstPullHoldsDefaultsAndRealEditWritesOnlyItsProfileSectionWithServerRevision',
        'testQueueSurvivesReopeningAndNetworkFailureWithoutChangingTheLocalBaseline',
        'testAnEditSavedBeforeAQueueFailureIsRecoveredAfterTheProcessReopens',
        'testAConcurrentRemoteLayoutWinsWholeAndTheParkedLocalVersionCanBeRestoredExplicitly',
        'testAnEditDuringAnAcceptedPushStaysQueuedAgainstTheNewServerRevision',
        'testRejectedPushParksTheLatestEditAndAdoptsTheServerWithoutDroppingItsNewFields',
        'testAResponseFromAnOldActivationCannotPublishAfterSwitchingAccountsAndQueuesRemainSeparate',
        'testAdoptionJournalRecoversAnInterruptedCommitWithoutEchoingServerData'],
    'CachedHouseholdLayoutTests': [
        'testEditingEachSharedSectionPreservesTheLatestOtherProfilesOpaqueFieldsAndOnlyDirtiesTheEditor',
        'testDeferredMappingAfterAnAcknowledgedLocalEditDoesNotCreateAnotherWrite',
        'testAnInterruptedAdoptionCannotReplaceANewerSharedProjectionWithTheSameVisibleFields'],
}
for suite, methods in affected.items():
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    for method in methods:
        assert len(re.findall(r'\bfunc ' + method + r'\(', source)) == 1
        cases.append('HarborTests.' + suite + '/' + method)
model_count = 30 if repair else 29
assert len(cases) == len(set(cases)) == model_count
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='CustomSource' + family, family=family,
        seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount',
        cases=['HarborExistingAppUITests.CustomSourceNavigationTests/testImportedDesktopFoldersOpenCatalogsEditImagesHideReopenAndDeleteOn' + family]))
    captures += ['source-' + state + '-' + family.lower() for state in ['imported', 'catalog', 'images-edited', 'hidden', 'restored', 'deleted']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=model_count, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=model_count + 4,
    expected_original_images=12, required_original_captures=captures, new_source_native_cases=model_count - 16, affected_page_native_cases=16,
    retained_identity_native_run=40222469616, retained_identity_ui_run=40219962030,
    original_desktop_parser_cases=12, original_desktop_click_cases=8, real_anonymous_trakt_native_get=True,
    owned_local_source_ui_server=True, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
if repair:
    plan.update(previous_unexecuted_compiler_run=40238599670, previous_actual_executions=0,
        new_guest_adoption_case=True, repaired_related_function_matches_retained_parent=True)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print(f'Custom sources:{model_count - 16}NEW+16AFFECTEDnative+2fresh+2NEW UI={model_count + 4}executions/12captures. No IPA or unrelated test replay.')

"""Select new source folders and only affected page persistence/synchronization cases."""
import json
import os
from pathlib import Path
import re

marker = 'affected:custom-sources'
cases = []
for suite, count in [('DesktopCustomSourceTests', 3), ('CustomSourceStorageTests', 6), ('CustomSourceProviderTests', 3), ('SourceFocusAnimationTests', 1), ('PageCustomizationScopeTests', 5)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8').split('final class ' + suite + ': XCTestCase {', 1)[1]
    methods = re.findall(r'\bfunc (test\w+)\(', source)
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
assert len(cases) == len(set(cases)) == 29
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='CustomSource' + family, family=family,
        seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount',
        cases=['HarborExistingAppUITests.CustomSourceNavigationTests/testImportedDesktopFoldersOpenCatalogsEditImagesHideReopenAndDeleteOn' + family]))
    captures += ['source-' + state + '-' + family.lower() for state in ['imported', 'catalog', 'images-edited', 'hidden', 'restored', 'deleted']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='custom-sources', selection_marker=marker,
    selected_case_count=29, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=33,
    expected_original_images=12, required_original_captures=captures, new_source_native_cases=13, affected_page_native_cases=16,
    retained_identity_native_run=40222469616, retained_identity_ui_run=40219962030,
    original_desktop_parser_cases=12, original_desktop_click_cases=8, real_anonymous_trakt_native_get=True,
    owned_local_source_ui_server=True, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Custom sources:13NEW+16AFFECTEDnative+2fresh+2NEW UI=33executions/12captures. No IPA or unrelated test replay.')
